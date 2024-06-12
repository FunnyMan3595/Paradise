use crate::constants::*;
use crate::model::*;
use crate::spring_chain;
use byondapi::map::ByondXYZ;
use eyre::eyre;
use scc::Bag;

/// Finds all the ways that air should not pass.
pub(crate) fn find_walls(next: &mut ZLevel) {
    for my_index in 0..MAP_SIZE * MAP_SIZE {
        let x = (my_index / MAP_SIZE) as i32;
        let y = (my_index % MAP_SIZE) as i32;

        for (dir_index, (dx, dy)) in AXES.iter().enumerate() {
            let maybe_their_index = ZLevel::maybe_get_index(x + dx, y + dy);
            let their_index;
            match maybe_their_index {
                Some(index) => their_index = index,
                None => {
                    // Edge of the map, acts like a wall.
                    let my_tile = next.get_tile_mut(my_index);
                    my_tile.wall[dir_index] = true;
                    continue;
                }
            }

            let (my_tile, their_tile) = next.get_pair_mut(my_index, their_index);
            if let AtmosMode::Space = my_tile.mode {
                if let AtmosMode::Space = their_tile.mode {
                    // We consider consecutive space tiles to be a wall, because two or more space
                    // tiles work the same as one.
                    my_tile.wall[dir_index] = true;
                    continue;
                }
            }

            if *dx > 0
                && (my_tile
                    .airtight_directions
                    .contains(AirtightDirections::EAST)
                    || their_tile
                        .airtight_directions
                        .contains(AirtightDirections::WEST))
            {
                // Something's blocking airflow.
                my_tile.wall[dir_index] = true;
                continue;
            } else if *dy > 0
                && (my_tile
                    .airtight_directions
                    .contains(AirtightDirections::NORTH)
                    || their_tile
                        .airtight_directions
                        .contains(AirtightDirections::SOUTH))
            {
                // Something's blocking airflow.
                my_tile.wall[dir_index] = true;
                continue;
            }
            my_tile.wall[dir_index] = false;
        }
    }
}

/// The core of the atmos engine: Moving gases around.
pub(crate) fn pressure_flow(prev: &ZLevel, next: &mut ZLevel) {
    // Loop through vertically.
    let mut y_chain = Chain::new(AXIS_Y);
    for index in 0..MAP_SIZE * MAP_SIZE {
        y_chain.progress(prev, next, index);
    }

    // Loop through horizontally.
    let mut x_chain = Chain::new(AXIS_X);
    for inv_index in 0..MAP_SIZE * MAP_SIZE {
        let y = (inv_index / MAP_SIZE) as i32;
        let x = (inv_index % MAP_SIZE) as i32;
        let index = (x * (MAP_SIZE as i32) + y) as usize;

        x_chain.progress(prev, next, index);
    }
}

/// Represents a chain of connected tiles along one axis.
pub(crate) struct Chain {
    axis: usize,
    started: bool,
    start_index: usize,
}

impl Chain {
    pub(crate) fn new(axis: usize) -> Self {
        Chain {
            axis,
            started: false,
            start_index: 0,
        }
    }

    /// Progress the chain based on the next tile. If a completed chain is found, call
    /// process_chain.
    pub(crate) fn progress(&mut self, prev: &ZLevel, next: &mut ZLevel, index: usize) {
        let mut complete = false;
        let mut should_restart = false;
        {
            let next_tile = next.get_tile(index);
            if !self.started && !next_tile.wall[self.axis] {
                // New chain.
                self.started = true;
                self.start_index = index;
            } else if self.started && next_tile.wall[self.axis] {
                // Completed chain.
                complete = true;
            } else if self.started && next_tile.mode == AtmosMode::Space {
                // This is a space tile between two non-space tiles.
                // End the prior chain here, but also start a new one.
                complete = true;
                should_restart = true;
            }
        }

        if !complete {
            return;
        }

        process_chain(prev, next, self.start_index, index, self.axis);
        if should_restart {
            self.start_index = index;
        } else {
            self.started = false;
        }
    }
}

/// Handles a single chain of connected tiles along one axis.
/// Updates momentum and moves air around based on it.
pub(crate) fn process_chain(
    prev: &ZLevel,
    next: &mut ZLevel,
    chain_start: usize,
    chain_end: usize,
    axis: usize,
) {
    let step: usize;
    if axis == AXIS_X {
        step = MAP_SIZE;
    } else {
        step = 1;
    }

    // Calculate the equilibrium point, i.e. where all the air would end up if we let the
    // pressure equalize (ignoring temperature changes).
    let mut equilibrium_positions: Vec<f32> = Vec::new();
    let start_is_space = prev.get_tile(chain_start).mode == AtmosMode::Space;
    let end_is_space = prev.get_tile(chain_end).mode == AtmosMode::Space;

    let tile_delta = (chain_end - chain_start) / step;
    let tiles = tile_delta + 1;
    let start_offset: f32 = 0.0;
    let end_offset = tiles as f32;
    let mut total_pressure: f32 = 0.0;

    for index in (chain_start..=chain_end).step_by(step) {
        total_pressure += prev.get_tile(index).pressure();
    }

    if total_pressure == 0.0 {
        // There's literally no air to move.
        return;
    }

    let mut accumulated_pressure: f32 = 0.0;
    for index in (chain_start..chain_end).step_by(step) {
        accumulated_pressure += prev.get_tile(index).pressure();
        equilibrium_positions.push(end_offset * accumulated_pressure / total_pressure);
    }

    // Use the equilibrium point as the air's "goal" and calculate the stress pulling it towards
    // that goal. (Or, equivalently, the force required to stretch the spring chain to that
    // extent.)
    let midpoint = (chain_start + chain_end) / 2;
    for (offset, index) in (chain_start..chain_end).step_by(step).enumerate() {
        let prev_tile = prev.get_tile(index);
        let moles = prev_tile.gases.moles().max(MINIMUM_NONZERO_MOLES);

        // Calculate the stress needed to reach the desired equilibrium.
        let mut left_position: f32 = start_offset;
        if offset > 0 {
            left_position = equilibrium_positions[offset - 1];
        }
        let left_moles = moles;

        let position = equilibrium_positions[offset];

        let prev_pos_tile = prev.get_tile(index + step);
        let mut right_position: f32 = end_offset;
        if offset + 1 < equilibrium_positions.len() {
            right_position = equilibrium_positions[offset + 1];
        }
        let right_moles = prev_pos_tile.gases.moles().max(MINIMUM_NONZERO_MOLES);

        let stress: f32;
        if start_is_space && end_is_space {
            if index < midpoint {
                stress = left_moles + right_moles;
            } else {
                stress = -(left_moles + right_moles);
            }
        } else if start_is_space {
            stress = left_moles + right_moles;
        } else if end_is_space {
            stress = -(left_moles + right_moles);
        } else {
            stress = -(position - left_position - 1.0) * left_moles
                + (right_position - position - 1.0) * right_moles;
        }

        // Update border momentum based on the stress.
        let tile = next.get_tile_mut(index);
        tile.momentum[axis] = tile.momentum[axis] * MOMENTUM_DECAY - stress;
    }

    // Get ready to run the solver.
    let mut momentum: Vec<f32> = Vec::new();
    let mut mole_counts: Vec<f32> = Vec::new();
    for index in (chain_start..=chain_end).step_by(step) {
        let prev_tile = prev.get_tile(index);
        let tile = next.get_tile_mut(index);

        // Remove the gas that we're about to redistribute.
        for gas in 0..GAS_COUNT {
            tile.gases.values[gas] -= prev_tile.gases.values[gas] / 2.0;
        }
        tile.gases.set_dirty();
        tile.thermal_energy -= prev_tile.thermal_energy / 2.0;

        // Collect the momentum, except for the last tile (since it's the momentum at the wall).
        if index != chain_end {
            momentum.push(tile.momentum[axis] * MOMENTUM_MULTIPLIER);
        }

        // Collect the mole count.
        // We pretend that tiles with less than MINIMUM_NONZERO_MOLES have that much gas instead,
        // to avoid breaking our solver by making some springs have no resistance.
        mole_counts.push(prev_tile.gases.moles().max(MINIMUM_NONZERO_MOLES));
    }

    // Run the solver.
    // In effect, this resizes each tile to match how the momentum stretches or compresses it.
    let mut displacements =
        spring_chain::solve(mole_counts, momentum, start_is_space, end_is_space);
    // Add the final wall onto the end.
    displacements.push(0.0);

    // Redistribute the gases into normal-size tiles.
    let mut left: f32 = 0.0;
    for (i, displacement) in displacements.iter().enumerate() {
        let right = ((i + 1) as f32 + displacement).min(end_offset);
        let prev_tile = prev.get_tile(chain_start + i * step);

        // These are different so that ranges like 0.0-1.0 correctly put both ends in the same
        // tile, even if both are off by a tiny amount.
        let start_offset = (left + 0.0001).floor() as usize;
        let end_offset = (right - 0.0001).floor().max(0.0) as usize;
        // We allow > so that ranges like 1.0-1.0 put all the gas in offset 0, to avoid trying to
        // access a tile beyond the grid.
        if start_offset >= end_offset {
            // All the air goes to one tile.
            let tile = next.get_tile_mut(chain_start + end_offset * step);
            for gas in 0..GAS_COUNT {
                tile.gases.values[gas] += prev_tile.gases.values[gas] / 2.0;
            }
            tile.thermal_energy += prev_tile.thermal_energy / 2.0;

            if right > left {
                left = right;
            }
            continue;
        }
        let size = right - left;
        for offset in start_offset..=end_offset {
            let offset_size: f32;
            if offset == start_offset {
                offset_size = (start_offset + 1) as f32 - left;
            } else if offset == end_offset {
                offset_size = right - end_offset as f32;
            } else {
                offset_size = 1.0;
            }

            // Give this tile its share of gas.
            let tile = next.get_tile_mut(chain_start + offset * step);
            for gas in 0..GAS_COUNT {
                tile.gases.values[gas] += 0.5 * prev_tile.gases.values[gas] * offset_size / size;
            }
            tile.thermal_energy += 0.5 * prev_tile.thermal_energy * offset_size / size;
        }

        if right > left {
            left = right;
        }
    }
}

/// Applies effects that happen after the main airflow routine:
/// * Tile modes
/// * Momentum scaling
/// * Superconductivity
/// * Reactions
/// * Sanitization
/// * Looking for interesting tiles.
pub(crate) fn post_process(
    prev: &ZLevel,
    next: &mut ZLevel,
    environments: &Box<[Tile]>,
    new_interesting_tiles: &Bag<InterestingTile>,
    z: i32,
) -> Result<(), eyre::Error> {
    for my_index in 0..MAP_SIZE * MAP_SIZE {
        let x = (my_index / MAP_SIZE) as i32;
        let y = (my_index % MAP_SIZE) as i32;
        let my_tile = prev.get_tile(my_index);

        let my_old_pressure = my_tile.pressure();
        let my_next_pressure;
        {
            let my_next_tile = next.get_tile_mut(my_index);
            apply_tile_mode(my_next_tile, environments)?;
            my_next_pressure = my_next_tile.pressure();
        }

        for (axis, (dx, dy)) in AXES.iter().enumerate() {
            if let Some(pos_index) = ZLevel::maybe_get_index(x + dx, y + dy) {
                let their_tile = prev.get_tile(pos_index);
                let their_old_pressure = their_tile.pressure();
                let (my_next_tile, their_next_tile) = next.get_pair_mut(my_index, pos_index);
                if my_old_pressure + their_old_pressure == 0.0 {
                    // No prior air.
                    my_next_tile.momentum[axis] = 0.0;
                    continue;
                }
                let their_next_pressure = their_next_tile.pressure();
                let pressure_scaling = (my_next_pressure + their_next_pressure)
                    / (my_old_pressure + their_old_pressure);
                my_next_tile.momentum[axis] *= pressure_scaling;
            }
        }

        if let AtmosMode::Space = my_tile.mode {
            // Space doesn't superconduct, has no reactions, doesn't need to be sanitized, and is never interesting. (Take that, astrophysicists and astronomers!)
            continue;
        }

        for (dx, dy) in AXES {
            let maybe_their_index = ZLevel::maybe_get_index(x + dx, y + dy);
            let their_index;
            match maybe_their_index {
                Some(index) => their_index = index,
                None => continue,
            }

            let (my_next_tile, their_next_tile) = next.get_pair_mut(my_index, their_index);

            if their_next_tile.mode != AtmosMode::Space {
                superconduct(my_next_tile, their_next_tile, dx > 0, false);
            }
        }

        let mut fuel_burnt;
        {
            let my_next_tile = next.get_tile_mut(my_index);

            // Track how much "fuel" was burnt across all reactions.
            fuel_burnt = react(my_next_tile, true);
            fuel_burnt += react(my_next_tile, false);

            // Sanitize the tile, to avoid negative/NaN/infinity spread.
            sanitize(my_next_tile, my_tile);
        }

        check_interesting(
            x,
            y,
            z,
            next,
            my_tile,
            my_index,
            fuel_burnt,
            new_interesting_tiles,
        )?;
    }
    Ok(())
}

pub(crate) fn sanitize(my_next_tile: &mut Tile, my_tile: &Tile) -> bool {
    let mut sanitized = false;
    for i in 0..GAS_COUNT {
        if !my_next_tile.gases.values[i].is_finite() {
            // Reset back to the last value, in the hopes that it's safe.
            my_next_tile.gases.values[i] = my_tile.gases.values[i];
            my_next_tile.gases.set_dirty();
            sanitized = true;
        } else if my_next_tile.gases.values[i] < 0.0 {
            // Zero out anything that becomes negative.
            my_next_tile.gases.values[i] = 0.0;
            my_next_tile.gases.set_dirty();
            sanitized = true;
        }
    }
    if !my_next_tile.thermal_energy.is_finite() {
        // Reset back to the last value, in the hopes that it's safe.
        my_next_tile.thermal_energy = my_tile.thermal_energy;
        sanitized = true;
    } else if my_next_tile.thermal_energy < 0.0 {
        // Zero out anything that becomes negative.
        my_next_tile.thermal_energy = 0.0;
        sanitized = true;
    }
    if !my_next_tile.momentum[0].is_finite() {
        // Reset back to the last value, in the hopes that it's safe.
        my_next_tile.momentum[0] = my_tile.momentum[0];
        sanitized = true;
    }
    if !my_next_tile.momentum[1].is_finite() {
        // Reset back to the last value, in the hopes that it's safe.
        my_next_tile.momentum[1] = my_tile.momentum[1];
        sanitized = true;
    }
    if my_next_tile.gases.moles() < MINIMUM_NONZERO_MOLES {
        for i in 0..GAS_COUNT {
            my_next_tile.gases.values[i] = 0.0;
        }
        my_next_tile.thermal_energy = 0.0;
        // We don't count this as sanitized because it's expected.
    }

    sanitized
}

#[allow(clippy::if_same_then_else)]
/// Checks a tile to see if it's "interesting" and should be sent to BYOND.
pub(crate) fn check_interesting(
    x: i32,
    y: i32,
    z: i32,
    next: &mut ZLevel,
    my_tile: &Tile,
    my_index: usize,
    fuel_burnt: f32,
    new_interesting_tiles: &Bag<InterestingTile>,
) -> Result<(), eyre::Error> {
    let mut reasons: ReasonFlags = ReasonFlags::empty();
    {
        let my_next_tile = next.get_tile_mut(my_index);
        if fuel_burnt > 0.0 {
            // FIRE!
            reasons |= ReasonFlags::DISPLAY;
        } else if (my_next_tile.gases.toxins() >= TOXINS_MIN_FIRE_AND_VISIBILITY_MOLES)
            != (my_tile.gases.toxins() >= TOXINS_MIN_FIRE_AND_VISIBILITY_MOLES)
        {
            // Crossed the toxins fire and visibility threshold.
            reasons |= ReasonFlags::DISPLAY;
        } else if (my_next_tile.gases.sleeping_agent() >= SLEEPING_GAS_VISIBILITY_MOLES)
            != (my_tile.gases.sleeping_agent() >= SLEEPING_GAS_VISIBILITY_MOLES)
        {
            // Crossed the sleeping agent visibility threshold.
            reasons |= ReasonFlags::DISPLAY;
        } else if (my_next_tile.gases.oxygen() >= OXYGEN_MIN_FIRE_MOLES)
            != (my_tile.gases.oxygen() >= OXYGEN_MIN_FIRE_MOLES)
        {
            // Crossed the oxygen fire threshold.
            reasons |= ReasonFlags::DISPLAY;
        } else if (my_next_tile.temperature() >= PLASMA_BURN_MIN_TEMP)
            != (my_tile.temperature() >= PLASMA_BURN_MIN_TEMP)
        {
            // Fire might have started or stopped.
            reasons |= ReasonFlags::DISPLAY;
        }

        if my_next_tile.temperature() > PLASMA_BURN_MIN_TEMP {
            if let AtmosMode::ExposedTo { .. } = my_next_tile.mode {
                // Since environments have fixed gases and temperatures, we only count them as
                // interesting (for heat) if there's an active fire.
                if fuel_burnt > 0.0 {
                    reasons |= ReasonFlags::HOT;
                }
            } else {
                // Anywhere else is interesting if it's hot enough to start a fire.
                reasons |= ReasonFlags::HOT;
            }
        }
    }
    let my_next_tile = next.get_tile(my_index);
    let mut wind_x: f32 = 0.0;
    if my_next_tile.momentum[AXIS_X] > 0.0 {
        wind_x += my_next_tile.momentum[AXIS_X] * WIND_MULTIPLIER;
    }
    if let Some(index) = ZLevel::maybe_get_index(x - 1, y) {
        let their_next_tile = next.get_tile(index);
        if their_next_tile.momentum[AXIS_X] < 0.0 {
            // This is negative, but that's good, because we want it to fight against the wind
            // towards +X.
            wind_x += their_next_tile.momentum[AXIS_X] * WIND_MULTIPLIER;
        }
    }
    let mut wind_y: f32 = 0.0;
    if my_next_tile.momentum[AXIS_Y] > 0.0 {
        wind_y += my_next_tile.momentum[AXIS_Y] * WIND_MULTIPLIER;
    }
    if let Some(index) = ZLevel::maybe_get_index(x, y - 1) {
        let their_next_tile = next.get_tile(index);
        if their_next_tile.momentum[AXIS_Y] < 0.0 {
            // This is negative, but that's good, because we want it to fight against the wind
            // towards +Y.
            wind_y += their_next_tile.momentum[AXIS_Y] * WIND_MULTIPLIER;
        }
    }
    if wind_x.powi(2) + wind_y.powi(2) > 1.0 {
        // Pressure flowing out of this tile might move stuff.
        reasons |= ReasonFlags::WIND;
    }

    if !reasons.is_empty() {
        // :eyes:
        new_interesting_tiles.push(InterestingTile {
            tile: my_next_tile.clone(),
            // +1 here to convert from our 0-indexing to BYOND's 1-indexing.
            coords: ByondXYZ::with_coords((x as i16 + 1, y as i16 + 1, z as i16 + 1)),
            reasons,
            wind_x,
            wind_y,
        });
    }

    Ok(())
}

/// Is the amount of gas present significant?
pub(crate) fn is_significant(tile: &Tile, gas: usize) -> bool {
    if tile.gases.values[gas] < REACTION_SIGNIFICANCE_MOLES {
        return false;
    }
    if gas != GAS_AGENT_B
        && tile.gases.values[gas] / tile.gases.moles() < REACTION_SIGNIFICANCE_RATIO
    {
        return false;
    }
    return true;
}

/// Perform chemical reactions on the tile.
pub(crate) fn react(my_next_tile: &mut Tile, hotspot_step: bool) -> f32 {
    let mut fuel_burnt: f32 = 0.0;

    let fraction: f32;
    let mut cached_heat_capacity: f32;
    let mut cached_temperature: f32;
    let mut thermal_energy: f32;
    if hotspot_step {
        if my_next_tile.hotspot_volume <= 0.0
            || my_next_tile.hotspot_temperature <= my_next_tile.temperature()
        {
            // No need for a hotspot.
            my_next_tile.hotspot_temperature = 0.0;
            my_next_tile.hotspot_volume = 0.0;
            return 0.0;
        }

        fraction = my_next_tile.hotspot_volume;
        cached_heat_capacity = fraction * my_next_tile.heat_capacity();
        cached_temperature = my_next_tile.hotspot_temperature;
        thermal_energy = cached_temperature * cached_heat_capacity;
    } else {
        fraction = 1.0 - my_next_tile.hotspot_volume;
        cached_heat_capacity = fraction * my_next_tile.heat_capacity();
        thermal_energy = my_next_tile.thermal_energy;
        cached_temperature = thermal_energy / cached_heat_capacity;
    }
    let initial_thermal_energy = thermal_energy;

    // Agent B converting CO2 to O2
    if cached_temperature > AGENT_B_CONVERSION_TEMP
        && is_significant(my_next_tile, GAS_AGENT_B)
        && is_significant(my_next_tile, GAS_CARBON_DIOXIDE)
        && is_significant(my_next_tile, GAS_TOXINS)
    {
        let co2_converted = fraction
            * (my_next_tile.gases.carbon_dioxide() * 0.75)
                .min(my_next_tile.gases.toxins() * 0.25)
                .min(my_next_tile.gases.agent_b() * 0.05);

        my_next_tile
            .gases
            .set_carbon_dioxide(my_next_tile.gases.carbon_dioxide() - co2_converted);
        my_next_tile
            .gases
            .set_oxygen(my_next_tile.gases.oxygen() + co2_converted);
        my_next_tile
            .gases
            .set_agent_b(my_next_tile.gases.agent_b() - co2_converted * 0.05);
        // Recalculate existing thermal energy to account for the change in heat capacity.
        cached_heat_capacity = fraction * my_next_tile.heat_capacity();
        thermal_energy = cached_temperature * cached_heat_capacity;
        // THEN we can add in the new thermal energy.
        thermal_energy += AGENT_B_CONVERSION_ENERGY * co2_converted;
        // Recalculate temperature for any subsequent reactions.
        cached_temperature = thermal_energy / cached_heat_capacity;
        fuel_burnt += co2_converted;
    }
    // Nitrous Oxide breaking down into nitrogen and oxygen.
    if cached_temperature > SLEEPING_GAS_BREAKDOWN_TEMP
        && is_significant(my_next_tile, GAS_SLEEPING_AGENT)
    {
        let reaction_percent = (0.00002
            * (cached_temperature - (0.00001 * (cached_temperature.powi(2)))))
        .max(0.0)
        .min(1.0);
        let nitrous_decomposed = reaction_percent * fraction * my_next_tile.gases.sleeping_agent();

        my_next_tile
            .gases
            .set_sleeping_agent(my_next_tile.gases.sleeping_agent() - nitrous_decomposed);
        my_next_tile
            .gases
            .set_nitrogen(my_next_tile.gases.nitrogen() + nitrous_decomposed);
        my_next_tile
            .gases
            .set_oxygen(my_next_tile.gases.oxygen() + nitrous_decomposed / 2.0);

        // Recalculate existing thermal energy to account for the change in heat capacity.
        cached_heat_capacity = fraction * my_next_tile.heat_capacity();
        thermal_energy = cached_temperature * cached_heat_capacity;
        // THEN we can add in the new thermal energy.
        thermal_energy += NITROUS_BREAKDOWN_ENERGY * nitrous_decomposed;
        // Recalculate temperature for any subsequent reactions.
        cached_temperature = thermal_energy / cached_heat_capacity;

        fuel_burnt += nitrous_decomposed;
    }
    // Plasmafire!
    if cached_temperature > PLASMA_BURN_MIN_TEMP
        && is_significant(my_next_tile, GAS_TOXINS)
        && is_significant(my_next_tile, GAS_OXYGEN)
    {
        // How efficient is the burn?
        // Linear scaling fom 0 to 1 as temperatue goes from minimum to optimal.
        let efficiency = ((cached_temperature - PLASMA_BURN_MIN_TEMP)
            / (PLASMA_BURN_OPTIMAL_TEMP - PLASMA_BURN_MIN_TEMP))
            .max(0.0)
            .min(1.0);

        // How much oxygen do we consume per plasma burnt?
        // Linear scaling from worst to best as efficiency goes from 0 to 1.
        let oxygen_per_plasma = PLASMA_BURN_WORST_OXYGEN_PER_PLASMA
            + (PLASMA_BURN_BEST_OXYGEN_PER_PLASMA - PLASMA_BURN_WORST_OXYGEN_PER_PLASMA)
                * efficiency;

        // How much plasma is available to burn?
        // Capped by oxygen availability. Significantly more oxygen is required than is
        // consumed. This means that if there is enough oxygen to burn all the plasma, the
        // oxygen-to-plasm ratio will increase while burning.
        let burnable_plasma = fraction
            * my_next_tile
                .gases
                .toxins()
                .min(my_next_tile.gases.oxygen() / PLASMA_BURN_REQUIRED_OXYGEN_AVAILABILITY);

        // Actual burn amount.
        let plasma_burnt = efficiency * PLASMA_BURN_MAX_RATIO * burnable_plasma;

        my_next_tile
            .gases
            .set_toxins(my_next_tile.gases.toxins() - plasma_burnt);
        my_next_tile
            .gases
            .set_carbon_dioxide(my_next_tile.gases.carbon_dioxide() + plasma_burnt);
        my_next_tile
            .gases
            .set_oxygen(my_next_tile.gases.oxygen() - plasma_burnt * oxygen_per_plasma);

        // Recalculate existing thermal energy to account for the change in heat capacity.
        cached_heat_capacity = fraction * my_next_tile.heat_capacity();
        thermal_energy = cached_temperature * cached_heat_capacity;
        // THEN we can add in the new thermal energy.
        thermal_energy += PLASMA_BURN_ENERGY * plasma_burnt;
        // Recalculate temperature for any subsequent reactions.
        // (or we would, but this is the last reaction)
        //cached_temperature = thermal_energy / cached_heat_capacity;

        fuel_burnt += plasma_burnt;
    }

    if hotspot_step {
        if fuel_burnt == 0.0 {
            // No need for a hotspot.
            // Dump the excess energy into the tile.
            my_next_tile.thermal_energy += thermal_energy
                - (my_next_tile.hotspot_temperature - my_next_tile.temperature())
                    * cached_heat_capacity;
            // Delete the hotspot.
            my_next_tile.hotspot_temperature = 0.0;
            my_next_tile.hotspot_volume = 0.0;
            return 0.0;
        }
        adjust_hotspot(
            my_next_tile,
            thermal_energy - my_next_tile.hotspot_temperature * cached_heat_capacity,
        );
    } else {
        my_next_tile.thermal_energy += thermal_energy - initial_thermal_energy;
    }

    fuel_burnt
}

/// Apply effects caused by the tile's atmos mode.
pub(crate) fn apply_tile_mode(
    my_next_tile: &mut Tile,
    environments: &Box<[Tile]>,
) -> Result<(), eyre::Error> {
    match my_next_tile.mode {
        AtmosMode::Space => {
            // Space tiles lose all gas and thermal energy every tick.
            for gas in 0..GAS_COUNT {
                my_next_tile.gases.values[gas] = 0.0;
            }
            my_next_tile.gases.set_dirty();
            my_next_tile.thermal_energy = 0.0;
        }
        AtmosMode::ExposedTo { environment_id } => {
            // Exposed tiles reset back to the same state every tick.
            if environment_id as usize > environments.len() {
                return Err(eyre!("Invalid environment ID {}", environment_id));
            }

            let environment = &environments[environment_id as usize];
            my_next_tile.gases.copy_from(&environment.gases);
            my_next_tile.thermal_energy = environment.thermal_energy;
        }
        AtmosMode::Sealed => {
            if my_next_tile.temperature() > PLASMA_BURN_MIN_TEMP {
                my_next_tile.thermal_energy -= SPACE_COOLING_CAPACITY;
                if my_next_tile.temperature() < TCMB {
                    my_next_tile.thermal_energy = TCMB * my_next_tile.heat_capacity();
                }
            }
        }
    }
    Ok(())
}

// Performs superconduction between two superconductivity-connected tiles.
pub(crate) fn superconduct(my_tile: &mut Tile, their_tile: &mut Tile, is_east: bool, force: bool) {
    // Superconduction is scaled to the smaller directional superconductivity setting of the two
    // tiles.
    let mut transfer_coefficient: f32;
    if force {
        transfer_coefficient = OPEN_HEAT_TRANSFER_COEFFICIENT;
    } else if is_east {
        transfer_coefficient = my_tile
            .superconductivity
            .east
            .min(their_tile.superconductivity.west);
    } else {
        transfer_coefficient = my_tile
            .superconductivity
            .north
            .min(their_tile.superconductivity.south);
    }

    let my_heat_capacity = my_tile.heat_capacity();
    let their_heat_capacity = their_tile.heat_capacity();
    if transfer_coefficient <= 0.0 || my_heat_capacity <= 0.0 || their_heat_capacity <= 0.0 {
        // Nothing to do.
        return;
    }

    // Temporary workaround to match LINDA better for high temperatures.
    if my_tile.temperature() > T20C || their_tile.temperature() > T20C {
        transfer_coefficient = (transfer_coefficient * 100.0).min(OPEN_HEAT_TRANSFER_COEFFICIENT);
    }

    // This is the formula from LINDA. I have no idea if it's a good one, I just copied it.
    // Positive means heat flow from us to them.
    // Negative means heat flow from them to us.
    let conduction = transfer_coefficient
        * (my_tile.temperature() - their_tile.temperature())
        * my_heat_capacity
        * their_heat_capacity
        / (my_heat_capacity + their_heat_capacity);

    // Half of the conduction always goes to the overall heat of the tile
    my_tile.thermal_energy -= conduction / 2.0;
    their_tile.thermal_energy += conduction / 2.0;

    // The other half can spawn or expand hotspots.
    if conduction > 0.0
        && my_tile.temperature() > PLASMA_BURN_OPTIMAL_TEMP
        && their_tile.temperature() < PLASMA_BURN_OPTIMAL_TEMP
    {
        // Positive: Spawn or expand their hotspot.
        adjust_hotspot(their_tile, conduction / 2.0);
        my_tile.thermal_energy -= conduction / 2.0;
    } else if conduction < 0.0
        && my_tile.temperature() < PLASMA_BURN_OPTIMAL_TEMP
        && their_tile.temperature() > PLASMA_BURN_OPTIMAL_TEMP
    {
        // Negative: Spawn or expand my hotspot.
        adjust_hotspot(my_tile, -conduction / 2.0);
        their_tile.thermal_energy += conduction / 2.0;
    } else {
        // No need for hotspot adjustmen.
        my_tile.thermal_energy -= conduction / 2.0;
        their_tile.thermal_energy += conduction / 2.0;
    }
}

// Adjusts the hotspot based on the given thermal energy delta.
// For positive values, the energy will first be used to reach PLASMA_BURN_OPTIMAL_TEMP, then
// to expand volume up to 1 (filled), and finally dumped into the tile's thermal energy.
// For negative values, only the hotspot's volume is affected.
pub(crate) fn adjust_hotspot(tile: &mut Tile, thermal_energy_delta: f32) {
    let cached_heat_capacity = tile.heat_capacity();

    if thermal_energy_delta < 0.0 {
        // Shrink volume accordingly.
        // How much heat do we need to fill the whole tile?
        let total_heat_needed = cached_heat_capacity * tile.hotspot_temperature;
        // How much heat do we have now?
        let heat_available = cached_heat_capacity * tile.hotspot_temperature * tile.hotspot_volume
            + thermal_energy_delta;
        // We fill that portion of the tile.
        tile.hotspot_volume = heat_available / total_heat_needed;
        return;
    }

    // Figure out how much heat we need to reach optimal temp.
    let temperature_delta =
        PLASMA_BURN_OPTIMAL_TEMP - tile.hotspot_temperature.min(PLASMA_BURN_OPTIMAL_TEMP);
    let heating_needed = cached_heat_capacity * temperature_delta;

    if heating_needed <= thermal_energy_delta {
        // Heat the hotspot to optimal.
        tile.hotspot_temperature = PLASMA_BURN_OPTIMAL_TEMP;
        let mut remaining_thermal_energy = thermal_energy_delta - heating_needed;

        // Expand to new volume.
        // How much heat do we need to fill the whole tile?
        let total_heat_needed = cached_heat_capacity * PLASMA_BURN_OPTIMAL_TEMP;
        // How hot is the tile?
        let tile_temperature = tile.thermal_energy / cached_heat_capacity;
        // How much thermal energy does the hotspot have, in addition to the tile's thermal energy?
        let hotspot_thermal_energy = cached_heat_capacity
            * tile.hotspot_volume
            * (tile.hotspot_temperature - tile_temperature);
        // How much heat do we have total?
        let heat_available =
            tile.thermal_energy + hotspot_thermal_energy + remaining_thermal_energy;
        if total_heat_needed <= heat_available {
            // We can fill the tile!
            // Overflow thermal energy.
            remaining_thermal_energy = heat_available - total_heat_needed;
            // Heat the tile up to match.
            tile.thermal_energy =
                cached_heat_capacity * PLASMA_BURN_OPTIMAL_TEMP + remaining_thermal_energy;
            // Destroy the hotspot.
            tile.hotspot_temperature = 0.0;
            tile.hotspot_volume = 0.0;
        } else {
            // Fill up the tile as much as we can.
            tile.hotspot_volume = heat_available / total_heat_needed;
        }
    } else {
        // Heat the hotspot as much as we can.
        tile.hotspot_temperature +=
            thermal_energy_delta / (tile.hotspot_volume * cached_heat_capacity);
    }
}

// Yay, tests!
#[cfg(test)]
mod tests {
    use super::*;
    // share_air() should do nothing to two space tiles.
    #[test]
    fn share_nothing() {
        let tile_a = Tile::new();
        let tile_b = Tile::new();

        let (gas_change, thermal_energy_change) = share_air(&tile_a, &tile_b, 1, 1);
        for i in 0..GAS_COUNT {
            assert_eq!(gas_change.values[i], 0.0, "{}", i);
        }
        assert_eq!(thermal_energy_change, 0.0);
    }

    // share_air() should do nothing to two matching tiles.
    #[test]
    fn share_equilibrium() {
        let mut tile_a = Tile::new();
        tile_a.gases.set_oxygen(80.0);
        tile_a.gases.set_nitrogen(20.0);
        tile_a.thermal_energy = 100.0;
        let mut tile_b = Tile::new();
        tile_b.gases.set_oxygen(80.0);
        tile_b.gases.set_nitrogen(20.0);
        tile_b.thermal_energy = 100.0;

        let (gas_change, thermal_energy_change) = share_air(&tile_a, &tile_b, 1, 1);
        for i in 0..GAS_COUNT {
            assert_eq!(gas_change.values[i], 0.0, "{}", i);
        }
        assert_eq!(thermal_energy_change, 0.0);
    }

    // share_air() should split air into 2 equal parts with connected_dirs of 1.
    #[test]
    fn share_splits_air_cd1() {
        let mut tile_a = Tile::new();
        tile_a.gases.set_oxygen(100.0);
        tile_a.thermal_energy = 100.0;
        let tile_b = Tile::new();

        let (gas_change, thermal_energy_change) = share_air(&tile_a, &tile_b, 1, 1);
        for i in 0..GAS_COUNT {
            if i == GAS_OXYGEN {
                assert_eq!(gas_change.values[i], -50.0);
            } else {
                assert_eq!(gas_change.values[i], 0.0, "{}", i);
            }
        }
        assert_eq!(thermal_energy_change, -50.0);
    }

    // share_air() should split air into 5 equal parts with connected_dirs of 4.
    #[test]
    fn share_splits_air_cd4() {
        let mut tile_a = Tile::new();
        tile_a.gases.set_oxygen(100.0);
        tile_a.thermal_energy = 100.0;
        let tile_b = Tile::new();

        let (gas_change, thermal_energy_change) = share_air(&tile_a, &tile_b, 4, 4);
        for i in 0..GAS_COUNT {
            if i == GAS_OXYGEN {
                assert_eq!(gas_change.values[i], -20.0);
            } else {
                assert_eq!(gas_change.values[i], 0.0, "{}", i);
            }
        }
        assert_eq!(thermal_energy_change, -20.0);
    }

    // superconduct() should transfer part of the thermal energy between two tiles that differ
    // only in thermal energy.
    #[test]
    fn superconduct_temperature() {
        let mut tile_a = Tile::new();
        tile_a.gases.set_oxygen(80.0);
        tile_a.gases.set_nitrogen(20.0);
        tile_a.thermal_energy = 100.0;
        let mut tile_b = Tile::new();
        tile_b.gases.set_oxygen(80.0);
        tile_b.gases.set_nitrogen(20.0);
        tile_b.thermal_energy = 200.0;

        superconduct(&mut tile_a, &mut tile_b, true, false);

        // These values are arbitrary, they're just what we get right now.
        // Update them if the calculations changed intentionally.
        assert_eq!(tile_a.thermal_energy, 120.0);
        assert_eq!(tile_b.thermal_energy, 180.0);
    }
}
