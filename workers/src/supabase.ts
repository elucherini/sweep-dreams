import type { SweepingSchedule } from './models';
import { SweepingScheduleSchema } from './models';

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
}
