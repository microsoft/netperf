import SvgColor from 'src/components/svg-color';

// ----------------------------------------------------------------------

const icon = (name) => (
  <SvgColor src={`/netperf/dist/assets/icons/navbar/${name}.svg`} sx={{ width: 1, height: 1 }} />
);

const navConfig = [
  {
    title: 'Overview',
    path: '/',
    icon: icon('ic_analytics'),
  },
  {
    title: 'detailed throughput',
    path: '/throughput',
    icon: icon('ic_analytics'),
  },
  {
    title: 'detailed latency',
    path: '/latency',
    icon: icon('ic_analytics'),
  },
  {
    title: 'Requests Per Second',
    path: '/rps',
    icon: icon('ic_analytics'),
  },
  {
    title: 'Handshakes Per Second',
    path: '/hps',
    icon: icon('ic_analytics'),
  },
  {
    title: 'Detailed Analysis',
    path: '/detailed',
    icon: icon('ic_analytics'),
  },
  // {
  //   title: 'product',
  //   path: '/products',
  //   icon: icon('ic_cart'),
  // },
  // {
  //   title: 'blog',
  //   path: '/blog',
  //   icon: icon('ic_blog'),
  // },
  // {
  //   title: 'login',
  //   path: '/login',
  //   icon: icon('ic_lock'),
  // },
  // {
  //   title: 'Not found',
  //   path: '/404',
  //   icon: icon('ic_disabled'),
  // },
];

export default navConfig;
