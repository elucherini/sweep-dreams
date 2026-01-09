import type { ParkingRegulation } from '../../shared/models/parking';
import type { SweepingSchedule, SubscriptionRecord } from '../../shared/models';
import { SupabaseClient } from '../../shared/supabase';
import { nextMoveDeadline, nextSweepWindow, formatPacificTime } from '../../shared/lib/calendar';
import { formatPacificClockTime } from './notify_formatting';
import { getFcmAccessToken, loadServiceAccountFromEnv, sendPushV1, shouldDryRun } from './lib/fcm';

type NotifyBindings = {
  SUPABASE_URL: string;
  SUPABASE_KEY: string;
  FCM_SERVICE_ACCOUNT_JSON?: string;
  FCM_PROJECT_ID?: string;
  NOTIFY_CADENCE_MINUTES?: string;
  NOTIFY_DRY_RUN?: string;
};

function parseCadenceMinutes(value: string | undefined): number {
  const parsed = Number.parseInt((value || '').trim(), 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 60;
}

function parseDateOrNull(value: string | null | undefined): Date | null {
  if (!value) return null;
  const dt = new Date(value);
  return Number.isFinite(dt.getTime()) ? dt : null;
}

function buildSweepingNotification(
  record: SubscriptionRecord,
  schedule: SweepingSchedule,
  start: Date,
  end: Date,
): { title: string; body: string; data: Record<string, string> } {
  const title = `Street sweeping on ${schedule.corridor} in ${record.lead_minutes} minutes!`;
  const locationParts: string[] = [schedule.corridor];
  if (schedule.limits) locationParts.push(`(${schedule.limits})`);
  if (schedule.block_side) locationParts.push(`- ${schedule.block_side} side`);
  const location = locationParts.join(' ');
  const body = `${location}: ${formatPacificClockTime(start)} - ${formatPacificClockTime(end)}`;
  return {
    title,
    body,
    data: {
      schedule_block_sweep_id: String(record.schedule_block_sweep_id),
      next_sweep_start: formatPacificTime(start),
      next_sweep_end: formatPacificTime(end),
    },
  };
}

function buildTimingNotification(
  record: SubscriptionRecord,
  regulation: ParkingRegulation,
  moveDeadline: Date,
): { title: string; body: string; data: Record<string, string> } {
  const hourLimit = regulation.hour_limit || 2;
  const title = `Move your car by ${formatPacificClockTime(moveDeadline)}`;
  let body = `${hourLimit}-hour limit ends at ${formatPacificClockTime(moveDeadline)}`;
  if (regulation.neighborhood) body = `${regulation.neighborhood}: ${body}`;
  return {
    title,
    body,
    data: {
      regulation_id: String(record.schedule_block_sweep_id),
      move_deadline: formatPacificTime(moveDeadline),
      subscription_type: 'timing',
    },
  };
}

function shouldSendSweeping(params: {
  record: SubscriptionRecord;
  schedule: SweepingSchedule;
  now: Date;
  cadenceMinutes: number;
}): { shouldSend: boolean; start: Date | null; end: Date | null; notifyAt: Date | null } {
  const { record, schedule, now, cadenceMinutes } = params;
  const [start, end] = nextSweepWindow(schedule, now);

  if (start.getTime() <= now.getTime()) {
    return { shouldSend: false, start, end, notifyAt: null };
  }

  const notifyAtIdeal = new Date(start.getTime() - record.lead_minutes * 60_000);
  const lastNotified = parseDateOrNull(record.last_notified_at ?? null);

  // Already notified for this sweep window
  if (lastNotified && lastNotified.getTime() >= notifyAtIdeal.getTime()) {
    return { shouldSend: false, start, end, notifyAt: null };
  }

  const windowStart = new Date(now.getTime() - cadenceMinutes * 60_000);

  // Send if notifyAtIdeal is within (windowStart, now] - i.e., first run at or after ideal time
  if (notifyAtIdeal.getTime() > windowStart.getTime() && notifyAtIdeal.getTime() <= now.getTime()) {
    return { shouldSend: true, start, end, notifyAt: notifyAtIdeal };
  }

  return { shouldSend: false, start, end, notifyAt: null };
}

function shouldSendTiming(params: {
  record: SubscriptionRecord;
  regulation: ParkingRegulation;
  now: Date;
  cadenceMinutes: number;
}): { shouldSend: boolean; moveDeadline: Date | null; notifyAt: Date | null } {
  const { record, regulation, now, cadenceMinutes } = params;
  const parkedAt = new Date(record.created_at);
  if (!Number.isFinite(parkedAt.getTime())) {
    return { shouldSend: false, moveDeadline: null, notifyAt: null };
  }

  try {
    const days = regulation.days;
    const hrsBegin = regulation.hrs_begin;
    const hrsEnd = regulation.hrs_end;
    const hourLimit = regulation.hour_limit;

    if (!days || hrsBegin === null || hrsEnd === null || hourLimit === null) {
      return { shouldSend: false, moveDeadline: null, notifyAt: null };
    }

    const moveDeadline = nextMoveDeadline(days, hrsBegin, hrsEnd, hourLimit, parkedAt);
    if (moveDeadline.getTime() <= now.getTime()) {
      return { shouldSend: false, moveDeadline, notifyAt: null };
    }

    const notifyAtIdeal = new Date(moveDeadline.getTime() - record.lead_minutes * 60_000);
    const alreadyNotified = parseDateOrNull(record.last_notified_at ?? null) !== null;

    // Already notified for this deadline
    if (alreadyNotified) {
      return { shouldSend: false, moveDeadline, notifyAt: null };
    }

    const windowStart = new Date(now.getTime() - cadenceMinutes * 60_000);

    // Send if notifyAtIdeal is within (windowStart, now] - i.e., first run at or after ideal time
    if (notifyAtIdeal.getTime() > windowStart.getTime() && notifyAtIdeal.getTime() <= now.getTime()) {
      return { shouldSend: true, moveDeadline, notifyAt: notifyAtIdeal };
    }

    return { shouldSend: false, moveDeadline, notifyAt: null };
  } catch {
    return { shouldSend: false, moveDeadline: null, notifyAt: null };
  }
}

export async function runNotificationSweep(env: NotifyBindings): Promise<{
  sent: number;
  skipped: number;
  dry_run: boolean;
}> {
  const cadenceMinutes = parseCadenceMinutes(env.NOTIFY_CADENCE_MINUTES);
  const now = new Date();

  const supabase = new SupabaseClient({
    url: env.SUPABASE_URL,
    key: env.SUPABASE_KEY,
  });

  const rawSa = (env.FCM_SERVICE_ACCOUNT_JSON || '').trim();
  const dryRun = shouldDryRun(env.NOTIFY_DRY_RUN) || !rawSa;

  const serviceAccount = rawSa ? loadServiceAccountFromEnv(rawSa, env.FCM_PROJECT_ID) : null;
  const accessToken = serviceAccount && !dryRun ? await getFcmAccessToken(serviceAccount) : '';

  console.log('Starting notification sweep', { now: now.toISOString(), cadenceMinutes, dryRun });

  const subscriptions = await supabase.listSubscriptions();
  console.log('Fetched subscriptions', { count: subscriptions.length });

  const sweepingIds = new Set<number>();
  const timingIds = new Set<number>();
  for (const record of subscriptions) {
    if (record.subscription_type === 'timing') timingIds.add(record.schedule_block_sweep_id);
    else sweepingIds.add(record.schedule_block_sweep_id);
  }

  const schedulesById = new Map<number, SweepingSchedule>();
  if (sweepingIds.size > 0) {
    const schedules = await supabase.getSchedulesByBlockSweepIds([...sweepingIds]);
    for (const s of schedules) schedulesById.set(s.block_sweep_id, s);
  }

  const regulationsById = new Map<number, ParkingRegulation>();
  if (timingIds.size > 0) {
    const regulations = await supabase.getParkingRegulationsByIds([...timingIds]);
    for (const r of regulations) regulationsById.set(r.id, r);
  }

  let sent = 0;
  let skipped = 0;

  for (const record of subscriptions) {
    try {
      if (record.subscription_type === 'timing') {
        const regulation = regulationsById.get(record.schedule_block_sweep_id);
        if (!regulation) {
          skipped += 1;
          continue;
        }

        const decision = shouldSendTiming({ record, regulation, now, cadenceMinutes });
        if (!decision.shouldSend || !decision.moveDeadline) {
          skipped += 1;
          continue;
        }

        const { title, body, data } = buildTimingNotification(record, regulation, decision.moveDeadline);
        await sendPushV1({
          accessToken,
          projectId: serviceAccount?.projectId || '',
          deviceToken: record.device_token,
          title,
          body,
          data,
          dryRun,
        });

        if (!dryRun) {
          await supabase.deleteSubscription(record.device_token, record.schedule_block_sweep_id);
        }

        sent += 1;
        continue;
      }

      const schedule = schedulesById.get(record.schedule_block_sweep_id);
      if (!schedule) {
        skipped += 1;
        continue;
      }

      const decision = shouldSendSweeping({ record, schedule, now, cadenceMinutes });
      if (!decision.shouldSend || !decision.start || !decision.end) {
        skipped += 1;
        continue;
      }

      const { title, body, data } = buildSweepingNotification(record, schedule, decision.start, decision.end);
      await sendPushV1({
        accessToken,
        projectId: serviceAccount?.projectId || '',
        deviceToken: record.device_token,
        title,
        body,
        data,
        dryRun,
      });

      if (!dryRun) {
        await supabase.markNotified(
          record.device_token,
          record.schedule_block_sweep_id,
          (decision.notifyAt || now).toISOString(),
        );
      }

      sent += 1;
    } catch (err) {
      console.error('Failed to process subscription', {
        device_token: record.device_token,
        schedule_block_sweep_id: record.schedule_block_sweep_id,
        subscription_type: record.subscription_type,
        err,
      });
      skipped += 1;
    }
  }

  console.log('Notification sweep done', { sent, skipped, dryRun });
  return { sent, skipped, dry_run: dryRun };
}
