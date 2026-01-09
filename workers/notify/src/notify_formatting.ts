const PACIFIC_TZ = 'America/Los_Angeles';

export function formatPacificClockTime(date: Date): string {
  return new Intl.DateTimeFormat('en-US', {
    timeZone: PACIFIC_TZ,
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
  }).format(date);
}
