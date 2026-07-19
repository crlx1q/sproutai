import os from 'os';

const c = {
  reset: '\x1b[0m',
  bold: '\x1b[1m',
  dim: '\x1b[2m',
  green: '\x1b[32m',
  brightGreen: '\x1b[92m',
  cyan: '\x1b[36m',
  yellow: '\x1b[33m',
  white: '\x1b[97m',
  gray: '\x1b[90m',
};

export function lanAddresses() {
  const result = [];
  for (const list of Object.values(os.networkInterfaces())) {
    for (const iface of list || []) {
      if (iface.family === 'IPv4' && !iface.internal) result.push(iface.address);
    }
  }
  return result;
}

function line(label, value) {
  return `${c.gray}│${c.reset}  ${c.dim}${label.padEnd(11)}${c.reset}${value}`;
}

export function printBanner(port) {
  const g = c.brightGreen;
  const url = (host) => `${c.cyan}http://${host}:${port}${c.reset}`;
  const lans = lanAddresses();

  const rows = [
    '',
    `${g}      🌱  S P R O U T   A I${c.reset}   ${c.dim}v1.0.0${c.reset}`,
    `${c.gray}┌────────────────────────────────────────────┐${c.reset}`,
    line('Статус', `${g}● онлайн${c.reset}  ${c.dim}(0.0.0.0:${port})${c.reset}`),
    line('Локально', url('localhost')),
    ...lans.map((ip) => line('В сети', `${url(ip)}  ${c.dim}← для телефона${c.reset}`)),
    line('Лендинг', url('localhost') + c.gray + '/' + c.reset),
    line('Админка', url('localhost') + c.gray + '/admin' + c.reset),
    line('API', url('localhost') + c.gray + '/api/health' + c.reset),
    `${c.gray}└────────────────────────────────────────────┘${c.reset}`,
    lans.length
      ? `${c.dim}   flutter run --dart-define=API_URL=http://${lans[0]}:${port}${c.reset}`
      : `${c.yellow}   Сетевые интерфейсы не найдены — доступен только localhost${c.reset}`,
    '',
  ];
  console.log(rows.join('\n'));
}
