import { DurableObject } from 'cloudflare:workers';
import { getFcmAccessToken, loadServiceAccountFromEnv, sendPushV1 } from '../shared/lib/fcm';
import { SupabaseClient } from '../shared/supabase';

export interface TimingPayload {
  deviceToken: string;
  scheduleBlockSweepId: number;
  title: string;
  body: string;
  data: Record<string, string>;
}

export interface TimingNotifierEnv {
  SUPABASE_URL: string;
  SUPABASE_KEY: string;
  FCM_SERVICE_ACCOUNT_JSON?: string;
  FCM_PROJECT_ID?: string;
}

export class TimingNotifier extends DurableObject<TimingNotifierEnv> {
  /**
   * Schedule an alarm to send a timing notification at a specific time.
   */
  async schedule(notifyAt: Date, payload: TimingPayload): Promise<void> {
    // Store payload for when alarm fires
    await this.ctx.storage.put('payload', payload);

    // Schedule alarm for exact notification time
    await this.ctx.storage.setAlarm(notifyAt);
  }

  /**
   * Cancel any scheduled alarm and clean up storage.
   */
  async cancel(): Promise<void> {
    await this.ctx.storage.deleteAlarm();
    await this.ctx.storage.deleteAll();
  }

  /**
   * Alarm handler - fires at the scheduled notification time.
   */
  async alarm(): Promise<void> {
    const payload = await this.ctx.storage.get<TimingPayload>('payload');
    if (!payload) {
      console.error('TimingNotifier alarm fired but no payload found');
      return;
    }

    try {
      // Send push notification
      const rawSa = (this.env.FCM_SERVICE_ACCOUNT_JSON || '').trim();
      if (!rawSa) {
        console.error('FCM_SERVICE_ACCOUNT_JSON not configured');
        return;
      }

      const serviceAccount = loadServiceAccountFromEnv(rawSa, this.env.FCM_PROJECT_ID);
      const accessToken = await getFcmAccessToken(serviceAccount);

      await sendPushV1({
        accessToken,
        projectId: serviceAccount.projectId,
        deviceToken: payload.deviceToken,
        title: payload.title,
        body: payload.body,
        data: payload.data,
        dryRun: false,
      });

      // Delete subscription from database (timing subscriptions are one-shot)
      const supabase = new SupabaseClient({
        url: this.env.SUPABASE_URL,
        key: this.env.SUPABASE_KEY,
      });
      await supabase.deleteSubscription(payload.deviceToken, payload.scheduleBlockSweepId);

      console.log('Timing notification sent', {
        deviceToken: payload.deviceToken.slice(0, 10) + '...',
        scheduleBlockSweepId: payload.scheduleBlockSweepId,
      });
    } catch (err) {
      console.error('Failed to send timing notification', err);
      // Don't retry - the deadline has passed and the notification window is gone
    } finally {
      // Clean up DO storage
      await this.ctx.storage.deleteAll();
    }
  }
}
