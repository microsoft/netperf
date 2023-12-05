// import { faker } from '@faker-js/faker';
// import Button from '@mui/material/Button';
import PropTypes from 'prop-types';

import Grid from '@mui/material/Unstable_Grid2';

// import Iconify from 'src/components/iconify';

// import AppTasks from '../app-tasks';
// import AppNewsUpdate from '../app-news-update';
// import AppOrderTimeline from '../app-order-timeline';
// import AppCurrentVisits from '../app-current-visits';
import AppWebsiteVisits from '../app-website-visits';

// import AppWidgetSummary from '../app-widget-summary';
// import AppTrafficBySite from '../app-traffic-by-site';
// import AppCurrentSubject from '../app-current-subject';
// import AppConversionRates from '../app-conversion-rates';

// ----------------------------------------------------------------------
function GraphView(props) {
  const { title, subheader, series, labels } = props;
  return (

        <Grid xs={12} md={6} lg={12}>
          <AppWebsiteVisits
            title={title}
            subheader={subheader}
            chart={{
              labels,
              series,
            }}
          />
        </Grid>
  );
}

GraphView.propTypes = {
  title: PropTypes.string.isRequired,
  subheader: PropTypes.string.isRequired,
  series: PropTypes.array.isRequired,
  labels: PropTypes.array.isRequired,
}

export default GraphView;
