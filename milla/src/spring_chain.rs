//! One of the core problems of airflow is how to redistribute the gas based on the known
//! velocities. Most obvious solutions to this become unstable under high velocity, leading to
//! checkerboard patterns of high and low air concentration, and potentially even oscillations that
//! produce increasingly negative and positive air concentrations.
//!
//! While this can be solved by putting limits on the velocity and restricting how much gas can
//! flow in each direction, that ultimately leads to somewhat sluggish airflow, enough so that the
//! room's vents can maintain pressure for a surprisingly long time.
//!
//! The solution chosen here is to allow half of each tile's air to flow along each axis, and then
//! model the air on each axis as a spring-chain problem. This problem can be visualized like this:
//! |-*-*-*-*-*-|
//! Legend (space station view):
//!   - is the air in a tile, consisting of `k` moles of gas.
//!   * is the border between tiles, with air flowing at velocity `v`.
//!   | is a boundary where no air will flow, either a solid object blocking airflow
//!     (wall, windoor, etc.) or the border between two space tiles.
//! Legend (spring-chain view):
//!   - is a spring, with spring constant `k` and rest length `d`=1.
//!   * is a mass. The quantity of mass isn't important, but there is a force `f` acting on each
//!     mass, with negative values pulling it left, and positive values pulling it right.
//!   | is a fixed mass at each end of the chain. The force acting on it is assumed to be zero, as
//!     no force would move it.
//!
//! To convert velocities into forces, we set `f = v * (k_left + k_right)`.
//!
//! The displacements of the springs will be used to "stretch" and "compress" the air into new
//! tiles. For example, if we have two tiles, meaning only one movable mass:
//! * If the displacement of the mass is 0, no air flows.
//! * If the displacement of the mass is -1 (matching the left boundary), the air from the left
//!   tile is all kept there, and half of the air from the right tile is added.
//! * If the displacement of the mass is 1 (matching the right boundary), the air from the right
//!   tile is all kept there, and half of the air from the left tile is added.
//! * At smaller values, less of the air is moved from the other tile.
//! Our solution to the spring-chain problem guarantees that the displacement will not cause any
//! mass to move beyond the next mass in either direction, including the boundaries.
//!
//! By modelling the air this way, we allow the air to be distributed along the entire chain of
//! tiles by the velocities, and large masses of air will easily push smaller masses along.
//!
//! Since solving the full linear equation for the spring chain is expensive, we use a simple
//! iterative approximation.

/// Approximates the displacements of the masses in a spring chain.
/// This is a naive solution that allows the masses to end up out of order.
///
/// Args:
///   * `k`: Spring constants k_0 to k_N-1.
///   * `f`: List of external forces acting on the middle masses (f_1 to f_N-2).
///          (f_0 and f_N-1 are assumed to be 0, as those masses are fixed in place)
///
/// Returns:
///   A vector containing the displacements of the middle masses (x_1 to x_N-2).
pub(crate) fn approximate_displacements(k: Vec<f32>, f: Vec<f32>) -> Vec<f32> {
    let mut displacements: Vec<f32> = Vec::new();
    // Assume all displacements are zero to start.
    for _ in 0..f.len() {
        displacements.push(0.0);
    }

    for _pass in 0..50 {
        let adjustment = relax(&k, &f, &mut displacements);
        if adjustment < 0.001 {
            break;
        }
    }

    displacements
}

pub(crate) fn relax(k: &Vec<f32>, f: &Vec<f32>, displacements: &mut Vec<f32>) -> f32 {
    let mut adjustment = 0.0;

    let mut left: f32 = 0.0;
    for i in 0..f.len() {
        let right: f32;
        if i == f.len() - 1 {
            // Border displacements are 0.
            right = 0.0;
        } else {
            right = displacements[i + 1];
        }

        // Update our guess.
        let old_guess = displacements[i];
        let strong_new_guess = (f[i] + left * k[i] + right * k[i + 1]) / (k[i] + k[i + 1]);
        let new_guess = (old_guess + old_guess + strong_new_guess) / 3.0;
        displacements[i] = new_guess;
        adjustment += (new_guess - old_guess).abs();

        // Save the new guess for the next iteration.
        left = new_guess;
    }

    adjustment
}

/// Given the displacements of a naive solution to the spring chain problem, calculates the
/// reduction factor R needed to return the masses to their initial ordering, while allowing
/// multiple masses to exist at the same point.
///
/// Args:
///   * `x`: List of initial displacements of the middle masses (x_1 to x_N-2), as an f32 slice.
///          x_0 and x_N-1 are assumed to be zero.
///
/// Returns:
///   The reduction factor R needed to adjust all external forces or, equivalently, all
///   displacements (f32).
pub(crate) fn calculate_reduction_factor(
    x: &Vec<f32>,
    unbound_start: bool,
    unbound_end: bool,
) -> f32 {
    // The maximum distance that two neighboring springs are inverted by.
    let mut max_inversion: f32 = 0.0;
    if !unbound_start {
        // x_0 is zero, so we have a simpler calculation here.
        let first_inversion = -x[0] - 1.0;
        max_inversion = max_inversion.max(first_inversion);
    }
    for i in 1..x.len() {
        // How far have these two masses been inverted by?
        // We only check the left side, as the right one will be handled by the next iteration.
        let left_inversion = x[i - 1] - x[i] - 1.0;

        max_inversion = max_inversion.max(left_inversion);
    }
    if !unbound_end {
        // Similar to first_inversion.
        let last_inversion = x[x.len() - 1] - 1.0;
        max_inversion = max_inversion.max(last_inversion);
    }

    max_inversion + 1.0
}

/// The main solver for our problem, combines approximate_displacements and
/// calculate_reduction_factor into a simple approximate solution.
pub(crate) fn solve(
    mole_counts: Vec<f32>,
    forces: Vec<f32>,
    unbound_start: bool,
    unbound_end: bool,
) -> Vec<f32> {
    // Build a naive solution.
    let mut solution = approximate_displacements(mole_counts, forces);

    // Scale it back to avoid the masses being out of order.
    let r = calculate_reduction_factor(&solution, unbound_start, unbound_end);
    for i in 0..solution.len() {
        solution[i] /= r
    }

    solution
}

#[cfg(test)]
mod tests {
    use super::*;
    const DISPLACEMENT_TOLERANCE: f32 = 0.1;

    #[test]
    fn approximate_displacements_simple() {
        let k: Vec<f32> = vec![1.0, 1.0, 1.0, 1.0];
        let f: Vec<f32> = vec![0.0, 0.0, 4.0/3.0];
        let displacements = approximate_displacements(k, f);
        assert_eq!(displacements.len(), 3);
        assert!((displacements[0] - (1.0/3.0)).abs() < DISPLACEMENT_TOLERANCE, "{:?}", displacements);
        assert!((displacements[1] - (2.0/3.0)).abs() < DISPLACEMENT_TOLERANCE, "{:?}", displacements);
        assert!((displacements[2] - 1.0).abs() < DISPLACEMENT_TOLERANCE, "{:?}", displacements);
    }

    #[test]
    fn approximate_displacements_doesnt_displace_without_forces() {
        let k: Vec<f32> = vec![1.0, 2.0, 3.0, 4.0];
        let f: Vec<f32> = vec![0.0, 0.0, 0.0];
        let displacements = approximate_displacements(k, f);
        for val in displacements {
            assert_eq!(val, 0.0);
        }
    }

    #[test]
    fn approximate_displacements_opposing_forces() {
        let k: Vec<f32> = vec![1.0, 1.0, 1.0];
        let f: Vec<f32> = vec![1.5, -1.5];
        let displacements = approximate_displacements(k, f);
        assert!((displacements[0] - 0.5).abs() < DISPLACEMENT_TOLERANCE, "{:?}", displacements);
        assert!((displacements[1] - -0.5).abs() < DISPLACEMENT_TOLERANCE, "{:?}", displacements);
    }

    #[test]
    fn approximate_displacements_respects_spring_constants() {
        let k: Vec<f32> = vec![1.0, 1.0, 2.0, 2.0];
        let f: Vec<f32> = vec![0.0, 3.0, 0.0];
        let displacements = approximate_displacements(k, f);
        assert!((displacements[0] - 1.0).abs() < DISPLACEMENT_TOLERANCE, "{:?}", displacements);
        assert!((displacements[1] - 2.0).abs() < DISPLACEMENT_TOLERANCE, "{:?}", displacements);
        assert!((displacements[2] - 1.0).abs() < DISPLACEMENT_TOLERANCE, "{:?}", displacements);
    }

    #[test]
    fn calculate_reduction_factor_simple() {
        let displacements: Vec<f32> = vec![2.0];
        assert_eq!(calculate_reduction_factor(&displacements, false, false), 2.0);
    }

    #[test]
    fn calculate_reduction_factor_opposing_forces() {
        let displacements: Vec<f32> = vec![1.0, -1.0];
        assert_eq!(calculate_reduction_factor(&displacements, false, false), 2.0);
    }

    #[test]
    fn calculate_reduction_factor_unbound_right() {
        let displacements: Vec<f32> = vec![2.0];
        assert_eq!(calculate_reduction_factor(&displacements, false, true), 1.0);
    }

    #[test]
    fn calculate_reduction_factor_unbound_left() {
        let displacements: Vec<f32> = vec![-2.0];
        assert_eq!(calculate_reduction_factor(&displacements, true, false), 1.0);
    }

    #[test]
    fn solve_simple() {
        let k: Vec<f32> = vec![1.0, 1.0, 1.0, 1.0];
        let f: Vec<f32> = vec![0.0, 0.0, 2.0];
        let displacements = solve(k, f, false, false);
        assert_eq!(displacements.len(), 3);
        assert!((displacements[0] - (1.0/3.0)).abs() < DISPLACEMENT_TOLERANCE, "{:?}", displacements);
        assert!((displacements[1] - (2.0/3.0)).abs() < DISPLACEMENT_TOLERANCE, "{:?}", displacements);
        assert!((displacements[2] - 1.0).abs() < DISPLACEMENT_TOLERANCE, "{:?}", displacements);
    }

    #[test]
    fn solve_with_reduction() {
        let k: Vec<f32> = vec![1.0, 1.0, 1.0, 1.0];
        let f: Vec<f32> = vec![0.0, 0.0, 4.0];
        let displacements = solve(k, f, false, false);
        assert_eq!(displacements.len(), 3);
        assert!((displacements[0] - (1.0/3.0)).abs() < DISPLACEMENT_TOLERANCE, "{:?}", displacements);
        assert!((displacements[1] - (2.0/3.0)).abs() < DISPLACEMENT_TOLERANCE, "{:?}", displacements);
        assert!((displacements[2] - 1.0).abs() < DISPLACEMENT_TOLERANCE, "{:?}", displacements);
    }
}
