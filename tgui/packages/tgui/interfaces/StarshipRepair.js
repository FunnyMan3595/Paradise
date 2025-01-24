import { useBackend, useLocalState } from '../backend';
import { Box, Button, Chart, ColorBox, Flex, Icon, LabeledList, ProgressBar, Section, Table } from '../components';
import { Window } from '../layouts';

export const StarshipRepair = (props, context) => {
  const { data } = useBackend(context);
  const { docked } = data;
  return (
    <Window width={600} height={650}>
      <Window.Content scrollable>
        <Box m={0}>{docked ? <StarshipRepairDocked /> : <StarshipRepairEmpty />}</Box>
      </Window.Content>
    </Window>
  );
};

const StarshipRepairEmpty = (props, context) => {
  const { act, data } = useBackend(context);
  return (
    <Box m={0}>
      <Button content="Request Damaged Ship" icon="circle-down" onClick={() => act('request')} />
    </Box>
  );
};

const StarshipRepairDocked = (props, context) => {
  const { act, data } = useBackend(context);
  return (
    <Box m={0}>
      <Button content="Check Completion" icon="list-check" onClick={() => act('complete')} />
    </Box>
  );
};
