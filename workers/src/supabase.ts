import type { SweepingSchedule, SubscriptionRecord } from './models';
import { SweepingScheduleSchema, SubscriptionRecordSchema } from './models';

export interface SupabaseConfig {
  url: string;
  key: string;
  table?: string;
  rpcFunction?: string;
}

export class SupabaseClient {
  private url: string;
  private key: string;
  private table: string;
  private rpcFunction: string;

  constructor(config: SupabaseConfig) {
    this.url = config.url;
    this.key = config.key;
    this.table = config.table || 'schedules';
    this.rpcFunction = config.rpcFunction || 'schedules_near';
  }

  /**
   * Call the schedules_near RPC function to find schedules near a point.
   *
   * @param latitude - Latitude of the point
   * @param longitude - Longitude of the point
   * @returns Array of sweeping schedules near the point
   */
  async closestSchedules(latitude: number, longitude: number): Promise<SweepingSchedule[]> {
    const rpcUrl = `${this.url}/rest/v1/rpc/${this.rpcFunction}`;

    const response = await fetch(rpcUrl, {
      method: 'POST',
      headers: {
        'apikey': this.key,
        'Authorization': `Bearer ${this.key}`,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: JSON.stringify({
        lon: longitude,
        lat: latitude,
      }),
    });

    if (!response.ok) {
      const text = await response.text();
      throw new Error(`Supabase RPC error ${response.status}: ${text}`);
    }

    const data = await response.json();

    // Validate with Zod
    if (!Array.isArray(data)) {
      throw new Error('Supabase RPC did not return an array');
    }

    return data.map((item: unknown) => SweepingScheduleSchema.parse(item));
  }

  /**
   * Get a specific schedule by block_sweep_id.
   *
   * @param blockSweepId - The block sweep ID
   * @returns The sweeping schedule
   */
  async getScheduleByBlockSweepId(blockSweepId: number): Promise<SweepingSchedule> {
    const url = `${this.url}/rest/v1/${this.table}?block_sweep_id=eq.${blockSweepId}&limit=1`;

    const response = await fetch(url, {
      method: 'GET',
      headers: {
        'apikey': this.key,
        'Authorization': `Bearer ${this.key}`,
        'Accept': 'application/json',
      },
    });

    if (!response.ok) {
      throw new Error(`Supabase query error ${response.status}`);
    }

    const data = await response.json();
    if (!Array.isArray(data) || data.length === 0) {
      throw new Error(`Schedule not found: ${blockSweepId}`);
    }

    return SweepingScheduleSchema.parse(data[0]);
  }

  /**
   * Upsert a subscription to the database.
   * Uses device_token as the unique constraint for upsert behavior.
   *
   * @param params - Subscription parameters
   * @returns The created/updated subscription record
   */
  async upsertSubscription(params: {
    deviceToken: string;
    platform: 'ios' | 'android' | 'web';
    scheduleBlockSweepId: number;
    latitude: number;
    longitude: number;
    leadMinutes: number;
  }): Promise<SubscriptionRecord> {
    const url = `${this.url}/rest/v1/subscriptions?on_conflict=device_token`;

    // Format location as PostGIS geography (SRID=4326;POINT(lon lat))
    const location = `SRID=4326;POINT(${params.longitude} ${params.latitude})`;

    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'apikey': this.key,
        'Authorization': `Bearer ${this.key}`,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Prefer': 'resolution=merge-duplicates,return=representation',
      },
      body: JSON.stringify([{
        device_token: params.deviceToken,
        platform: params.platform,
        schedule_block_sweep_id: params.scheduleBlockSweepId,
        location: location,
        lead_minutes: params.leadMinutes,
      }]),
    });

    if (!response.ok) {
      const text = await response.text();
      throw new Error(`Supabase upsert error ${response.status}: ${text}`);
    }

    const data = await response.json();
    if (!Array.isArray(data) || data.length === 0) {
      throw new Error('Supabase upsert did not return a record');
    }

    return SubscriptionRecordSchema.parse(data[0]);
  }

  /**
   * Get a subscription by device token.
   *
   * @param deviceToken - The device token
   * @returns The subscription record, or null if not found
   */
  async getSubscriptionByDeviceToken(deviceToken: string): Promise<SubscriptionRecord | null> {
    const url = `${this.url}/rest/v1/subscriptions?device_token=eq.${encodeURIComponent(deviceToken)}&limit=1`;

    const response = await fetch(url, {
      method: 'GET',
      headers: {
        'apikey': this.key,
        'Authorization': `Bearer ${this.key}`,
        'Accept': 'application/json',
      },
    });

    if (!response.ok) {
      const text = await response.text();
      throw new Error(`Supabase query error ${response.status}: ${text}`);
    }

    const data = await response.json();
    if (!Array.isArray(data) || data.length === 0) {
      return null;
    }

    return SubscriptionRecordSchema.parse(data[0]);
  }

  /**
   * Delete a subscription by device token.
   *
   * @param deviceToken - The device token
   * @returns true if deleted, false if not found
   */
  async deleteSubscription(deviceToken: string): Promise<boolean> {
    const url = `${this.url}/rest/v1/subscriptions?device_token=eq.${encodeURIComponent(deviceToken)}`;

    const response = await fetch(url, {
      method: 'DELETE',
      headers: {
        'apikey': this.key,
        'Authorization': `Bearer ${this.key}`,
        'Accept': 'application/json',
        'Prefer': 'return=representation',
      },
    });

    if (!response.ok) {
      const text = await response.text();
      throw new Error(`Supabase delete error ${response.status}: ${text}`);
    }

    const data = await response.json();
    return Array.isArray(data) && data.length > 0;
  }
}
