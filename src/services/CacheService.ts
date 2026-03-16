import AsyncStorage from '@react-native-async-storage/async-storage';

const CACHE_PREFIX = 'm3ue_cache_';
const SETTINGS_KEY = 'm3ue_cache_settings';

export interface CacheSettings {
  refreshIntervalMinutes: number;
}

interface CacheEntry<T> {
  data: T;
  timestamp: number;
}

const DEFAULT_SETTINGS: CacheSettings = {
  refreshIntervalMinutes: 60,
};

type CacheKey =
  | 'categories'
  | 'liveStreams'
  | `liveStreams_${string}`
  | 'vodStreams'
  | `vodStreams_${string}`
  | 'series'
  | `series_${string}`
  | `vodInfo_${number}`
  | `seriesInfo_${number}`;

class CacheService {
  private settings: CacheSettings = DEFAULT_SETTINGS;

  async loadSettings(): Promise<CacheSettings> {
    try {
      const raw = await AsyncStorage.getItem(SETTINGS_KEY);
      if (raw) {
        this.settings = { ...DEFAULT_SETTINGS, ...JSON.parse(raw) };
      }
    } catch {
      this.settings = DEFAULT_SETTINGS;
    }
    return this.settings;
  }

  async saveSettings(settings: CacheSettings): Promise<void> {
    this.settings = settings;
    await AsyncStorage.setItem(SETTINGS_KEY, JSON.stringify(settings));
  }

  getSettings(): CacheSettings {
    return this.settings;
  }

  async get<T>(key: CacheKey): Promise<{ data: T; isStale: boolean } | null> {
    try {
      const raw = await AsyncStorage.getItem(CACHE_PREFIX + key);
      if (!raw) return null;

      const entry: CacheEntry<T> = JSON.parse(raw);
      const ageMs = Date.now() - entry.timestamp;
      const maxAgeMs = this.settings.refreshIntervalMinutes * 60 * 1000;

      return {
        data: entry.data,
        isStale: ageMs > maxAgeMs,
      };
    } catch {
      return null;
    }
  }

  async set<T>(key: CacheKey, data: T): Promise<void> {
    const entry: CacheEntry<T> = {
      data,
      timestamp: Date.now(),
    };
    try {
      await AsyncStorage.setItem(CACHE_PREFIX + key, JSON.stringify(entry));
    } catch {
      // Storage full or unavailable — silently ignore
    }
  }

  async clear(): Promise<void> {
    try {
      const keys = await AsyncStorage.getAllKeys();
      const cacheKeys = keys.filter((k) => k.startsWith(CACHE_PREFIX));
      if (cacheKeys.length > 0) {
        await AsyncStorage.multiRemove(cacheKeys);
      }
    } catch {
      // ignore
    }
  }
}

export const cacheService = new CacheService();
