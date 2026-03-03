/**
 * EPGScreen – Custom TV-optimised Electronic Programme Guide
 *
 * Architecture overview:
 *  • Single hidden View (hasTVPreferredFocus) captures all remote input so
 *    native focus traversal never interferes with the custom grid navigation.
 *  • All D-pad navigation is handled via TVEventHandler, giving identical
 *    behaviour on Android TV and tvOS without platform-specific scaling quirks.
 *  • Rows are virtualised with a manual windowed view (avoids tvOS FlatList
 *    rendering bugs with scrollEnabled={false}).
 *  • Programs within each row are absolute-positioned in a wide "track" View
 *    that is shifted horizontally via a shared scrollX value.
 *  • EPG data is loaded lazily as the visible channel window changes.
 *
 * Focus modes:
 *  'sidebar'  – Up/Down moves between channels. Right/Select enters the grid.
 *  'grid'     – Up/Down changes row (horizontal position preserved).
 *               Left/Right moves between programmes.
 *               Back/Menu returns to sidebar.
 *               Left at col=0 (no earlier programme) returns to sidebar.
 */

import React, {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';
import {
  View,
  Text,
  StyleSheet,
  BackHandler,
  TVEventHandler,
  useWindowDimensions,
  ActivityIndicator,
  Image,
} from 'react-native';
import { useIsFocused } from '@react-navigation/native';
import { useXtream } from '../context/XtreamContext';
import { xtreamService } from '../services/XtreamService';
import { useMenu } from '../context/MenuContext';
import { SIDEBAR_WIDTH_COLLAPSED } from '../components/SideBar';
import { colors } from '../theme';
import { DrawerScreenPropsType } from '../navigation/types';
import { XtreamLiveStream, XtreamEpgListing } from '../types/xtream';
import { scaledPixels } from '../hooks/useScale';

// ─── Layout constants (designed at 1920 × 1080) ─────────────────────────────
const SIDEBAR_WIDTH = scaledPixels(260);
const CHANNEL_HEIGHT = scaledPixels(80);
const TIME_HEADER_HEIGHT = scaledPixels(52);
const PIXELS_PER_MIN = scaledPixels(6); // 6 design-px per minute
const PAST_MINUTES = 120; // 2 h of past programmes visible
const FUTURE_MINUTES = 480; // 8 h of future programmes visible
const TOTAL_MINUTES = PAST_MINUTES + FUTURE_MINUTES;
const TOTAL_TRACK_WIDTH = TOTAL_MINUTES * PIXELS_PER_MIN;
const NOW_LEFT = PAST_MINUTES * PIXELS_PER_MIN; // pixel offset of "now" on the track

// How many pixels to scroll left/right when already at col boundary
const SCROLL_STEP = scaledPixels(300);

// ─── Types ───────────────────────────────────────────────────────────────────
interface Channel {
  uuid: string;
  title: string;
  logo: string;
}

interface EpgProgram {
  id: string;
  channelUuid: string;
  title: string;
  since: Date;
  till: Date;
  /** Pixels from the start of the timeline track */
  left: number;
  /** Pixels wide */
  width: number;
}

type FocusMode = 'sidebar' | 'grid';

// ─── Utilities ───────────────────────────────────────────────────────────────
const decodeBase64 = (str: string): string => {
  try {
    const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
    let output = '';
    const s = str.replace(/[^A-Za-z0-9+/=]/g, '');
    for (let i = 0; i < s.length;) {
      const e1 = chars.indexOf(s.charAt(i++));
      const e2 = chars.indexOf(s.charAt(i++));
      const e3 = chars.indexOf(s.charAt(i++));
      const e4 = chars.indexOf(s.charAt(i++));
      output += String.fromCharCode((e1 << 2) | (e2 >> 4));
      if (e3 !== 64) output += String.fromCharCode(((e2 & 15) << 4) | (e3 >> 2));
      if (e4 !== 64) output += String.fromCharCode(((e3 & 3) << 6) | e4);
    }
    return decodeURIComponent(escape(output));
  } catch {
    return str;
  }
};

const fmt12h = (d: Date): string => {
  const h = d.getHours();
  const m = d.getMinutes().toString().padStart(2, '0');
  return `${h % 12 || 12}:${m} ${h >= 12 ? 'PM' : 'AM'}`;
};

const clamp = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v));

/** Convert EPG listing array → positioned EpgProgram array for one channel */
const buildPrograms = (
  uuid: string,
  listings: XtreamEpgListing[],
  rangeStart: Date,
): EpgProgram[] => {
  if (!listings?.length) return [];
  const programs: EpgProgram[] = [];

  listings.forEach((l) => {
    if (!l?.id || !l.start_timestamp || !l.stop_timestamp) return;
    const since = new Date(Number(l.start_timestamp) * 1000);
    const till = new Date(Number(l.stop_timestamp) * 1000);
    if (isNaN(since.getTime()) || isNaN(till.getTime())) return;

    const startMins = (since.getTime() - rangeStart.getTime()) / 60_000;
    const endMins = (till.getTime() - rangeStart.getTime()) / 60_000;
    const left = startMins * PIXELS_PER_MIN;
    const width = (endMins - startMins) * PIXELS_PER_MIN;
    if (width < 2) return;
    // Skip programmes that are entirely before the start or at/beyond the end of
    // the visible track.  Without this guard:
    //  • left + width ≤ 0  → programme is off-screen left; navigating to it
    //    requires multiple Left presses before reaching col 0.
    //  • left ≥ TOTAL_TRACK_WIDTH → programme starts after the track ends;
    //    scrollToProgram clamps scrollX and the block renders off-screen right.
    if (left + width <= 0) return;
    if (left >= TOTAL_TRACK_WIDTH) return;

    programs.push({
      id: `${uuid}-${l.id}`,
      channelUuid: uuid,
      title: decodeBase64(String(l.title || 'No Title')),
      since,
      till,
      left,
      width,
    });
  });

  return programs.sort((a, b) => a.left - b.left);
};

// ─── Sub-components ───────────────────────────────────────────────────────────

/** Horizontal time ruler */
const TimeRuler = React.memo(
  ({
    rangeStart,
    scrollX,
    viewportWidth,
  }: {
    rangeStart: Date;
    scrollX: number;
    viewportWidth: number;
  }) => {
    const markers: React.ReactNode[] = [];
    // Align marks to real clock :00/:30 boundaries, not intervals from rangeStart.
    // rangeStart is `now - 2h` and has non-zero minutes, so naive 30-min increments
    // from it would produce labels like ":35 :05 :35 :05".
    const MARK_MS = 30 * 60 * 1000;
    const rangeStartMs = rangeStart.getTime();
    const visStartMs = rangeStartMs + (scrollX / PIXELS_PER_MIN) * 60_000;
    const visEndMs = rangeStartMs + ((scrollX + viewportWidth) / PIXELS_PER_MIN) * 60_000;
    // One extra slot of overscan on each side
    const firstMarkMs = Math.floor((visStartMs - MARK_MS) / MARK_MS) * MARK_MS;
    const lastMarkMs = Math.ceil((visEndMs + MARK_MS) / MARK_MS) * MARK_MS;

    for (let ms = firstMarkMs; ms <= lastMarkMs; ms += MARK_MS) {
      const minsFromStart = (ms - rangeStartMs) / 60_000;
      const left = minsFromStart * PIXELS_PER_MIN - scrollX;
      if (left < -scaledPixels(120) || left > viewportWidth + scaledPixels(120)) continue;
      const t = new Date(ms);
      const isHour = t.getMinutes() === 0;
      markers.push(
        <View key={ms} style={[styles.timeMarker, { left }]}>
          <Text style={[styles.timeMarkerText, !isHour && styles.timeMarkerHalf]}>
            {isHour ? fmt12h(t) : `:${t.getMinutes().toString().padStart(2, '0')}`}
          </Text>
          <View style={[styles.timeMarkerTick, !isHour && styles.timeMarkerTickHalf]} />
        </View>,
      );
    }

    const nowScreenX = NOW_LEFT - scrollX;

    return (
      <View style={[styles.timeRuler, { width: viewportWidth }]}>
        {markers}
        {nowScreenX >= 0 && nowScreenX <= viewportWidth && (
          <View style={[styles.nowTickInRuler, { left: nowScreenX }]} />
        )}
      </View>
    );
  },
);

/** One channel row: logo/title sidebar + programme blocks */
interface ChannelRowProps {
  channel: Channel;
  programs: EpgProgram[];
  isEpgLoading: boolean;
  sidebarFocused: boolean;
  focusedProgramIdx: number;
  scrollX: number;
  viewportWidth: number;
  isCurrentRow: boolean;
  isGridMode: boolean;
}

const ChannelRow = React.memo(
  ({
    channel,
    programs,
    isEpgLoading,
    sidebarFocused,
    focusedProgramIdx,
    scrollX,
    viewportWidth,
    isCurrentRow,
    isGridMode,
  }: ChannelRowProps) => {
    // Only render programmes that overlap the visible viewport (+ overscan)
    const visiblePrograms = useMemo(() => {
      const lo = scrollX - viewportWidth;
      const hi = scrollX + viewportWidth * 2;
      return programs.filter((p) => p.left + p.width > lo && p.left < hi);
    }, [programs, scrollX, viewportWidth]);

    const nowScreenX = NOW_LEFT - scrollX;

    return (
      <View style={[
        styles.channelRow,
        isCurrentRow && isGridMode && styles.channelRowGridActive,
      ]}>
        {/* ── Sidebar cell ── */}
        <View
          style={[
            styles.sidebarCell,
            isCurrentRow && styles.sidebarCellHighlight,
            sidebarFocused && styles.sidebarCellFocused,
          ]}
        >
          {channel.logo ? (
            <Image
              source={{ uri: channel.logo }}
              style={styles.channelLogo}
              resizeMode="contain"
            />
          ) : null}
          <Text style={[styles.channelTitle, sidebarFocused && styles.channelTitleFocused]} numberOfLines={2}>
            {channel.title}
          </Text>
        </View>

        {/* ── Programme viewport ── */}
        <View style={styles.programViewport}>
          {/* "Now" vertical bar */}
          {nowScreenX >= 0 && nowScreenX <= viewportWidth && (
            <View style={[styles.nowBarRow, { left: nowScreenX }]} />
          )}

          {isEpgLoading ? (
            <View style={styles.epgLoadingRow}>
              <ActivityIndicator size="small" color={colors.textTertiary} />
            </View>
          ) : programs.length === 0 ? (
            <View style={styles.noDataRow}>
              <Text style={styles.noDataText}>No EPG data</Text>
            </View>
          ) : (
            visiblePrograms.map((program) => {
              const globalIdx = programs.indexOf(program);
              const focused = isCurrentRow && isGridMode && globalIdx === focusedProgramIdx;
              const rawLeft = program.left - scrollX;
              // Clamp to 0 so programs that started before the current scroll
              // position never bleed left into the sidebarCell area. Trim width
              // by the same amount so the block ends at the correct time.
              const blockLeft = Math.max(rawLeft, 0);
              const clampedWidth = Math.max(
                program.width - scaledPixels(3) - (blockLeft - rawLeft),
                4,
              );

              return (
                <View
                  key={program.id}
                  style={[
                    styles.programBlock,
                    { left: blockLeft, width: clampedWidth },
                    focused && styles.programBlockFocused,
                  ]}
                >
                  <Text
                    style={[styles.programTitle, focused && styles.programTitleFocused]}
                    numberOfLines={1}
                  >
                    {program.title}
                  </Text>
                  <Text style={[styles.programTime, focused && styles.programTimeFocused]} numberOfLines={1}>
                    {fmt12h(program.since)}
                  </Text>
                </View>
              );
            })
          )}
        </View>
      </View>
    );
  },
  (prev, next) =>
    prev.sidebarFocused === next.sidebarFocused &&
    prev.focusedProgramIdx === next.focusedProgramIdx &&
    prev.scrollX === next.scrollX &&
    prev.isEpgLoading === next.isEpgLoading &&
    prev.programs === next.programs &&
    prev.isCurrentRow === next.isCurrentRow &&
    prev.isGridMode === next.isGridMode,
);

// ─── Focus-capture element ────────────────────────────────────────────────────
/**
 * An invisible, always-present focusable View that holds TV preferred focus.
 * This keeps all D-pad input flowing to our TVEventHandler without native
 * focus traversal jumping to arbitrary on-screen elements.
 */
/** Pass active={false} to release focus capture so the app nav sidebar can be reached. */
const FocusCapture = React.memo(({ active }: { active: boolean }) => (
  <View
    focusable={active}
    // @ts-ignore – hasTVPreferredFocus is a TV-only prop
    hasTVPreferredFocus={active}
    accessible={false}
    style={styles.focusCapture}
  />
));

// ─── Main Screen ─────────────────────────────────────────────────────────────

export function EPGScreen({ navigation }: DrawerScreenPropsType<'EPG'>) {
  const isFocused = useIsFocused();
  const { width: screenWidth, height: screenHeight } = useWindowDimensions();
  // The content container in AppNavigator has marginLeft: SIDEBAR_WIDTH_COLLAPSED,
  // so the EPG's true available width is screenWidth minus that margin.
  const viewportWidth = screenWidth - SIDEBAR_WIDTH_COLLAPSED - SIDEBAR_WIDTH;

  const { isConfigured, liveStreams, fetchLiveStreams } = useXtream();
  const { setSidebarActive, isSidebarActive } = useMenu();
  // Ref copy so the TVEventHandler and BackHandler never capture a stale closure.
  const isSidebarActiveRef = useRef(false);

  // ── Data state ──────────────────────────────────────────────────────────
  const [isLoadingChannels, setIsLoadingChannels] = useState(true);
  const [channels, setChannels] = useState<Channel[]>([]);
  const [epgMap, setEpgMap] = useState<Record<string, EpgProgram[]>>({});
  const [loadingEpgIds, setLoadingEpgIds] = useState<Set<string>>(new Set());
  const fetchedIds = useRef<Set<string>>(new Set());

  // ── Navigation state ──────────────────────────────────────────────────
  // Start in sidebar mode so user picks a channel first; the grid is entered
  // on Right/Select, at which point EPG data is likely already loaded.
  const [focusMode, setFocusMode] = useState<FocusMode>('sidebar');
  const [focusedRow, setFocusedRow] = useState(0);
  const [focusedCol, setFocusedCol] = useState(0);
  const [scrollX, setScrollX] = useState(0);

  // Mutable refs – avoid stale closures in the TVEventHandler callback
  const focusModeRef = useRef<FocusMode>('sidebar');
  const focusedRowRef = useRef(0);
  const focusedColRef = useRef(0);
  const scrollXRef = useRef(0);
  const channelsRef = useRef<Channel[]>([]);
  const epgMapRef = useRef<Record<string, EpgProgram[]>>({});

  // Tracks whether the user has manually navigated in the grid.
  // Prevents the EPG-load effect from resetting col after the user has moved.
  const hasManuallyNavigated = useRef(false);

  // ── Vertical scroll state (replaces FlatList – avoids tvOS rendering bugs) ──
  const [scrollY, setScrollY] = useState(0);
  const scrollYRef = useRef(0);
  // Kept in sync with (screenHeight - TIME_HEADER_HEIGHT) so the TVEventHandler
  // can compute scroll offsets without capturing stale render-time values.
  const listHeightRef = useRef(0);

  // ── Dismiss the nav drawer whenever this screen is focused ───────────
  useEffect(() => {
    if (isFocused) setSidebarActive(false);
  }, [isFocused, setSidebarActive]);

  // ── Keep isSidebarActiveRef in sync (avoids stale closures in handlers) ──
  useEffect(() => {
    isSidebarActiveRef.current = isSidebarActive;
  }, [isSidebarActive]);

  // ── Keep listHeightRef in sync so the TVEventHandler can scroll correctly ──
  useEffect(() => {
    listHeightRef.current = Math.max(0, screenHeight - TIME_HEADER_HEIGHT);
  }, [screenHeight]);

  // ── Timeline anchor (computed once) ──────────────────────────────────
  const rangeStart = useMemo(() => {
    const now = new Date();
    return new Date(now.getTime() - PAST_MINUTES * 60_000);
  }, []);

  // ── EPG fetching ──────────────────────────────────────────────────────
  const fetchEpgForChannels = useCallback(
    async (uuids: string[]) => {
      const toFetch = uuids.filter((id) => !fetchedIds.current.has(id));
      if (!toFetch.length) return;

      toFetch.forEach((id) => fetchedIds.current.add(id));
      setLoadingEpgIds((prev) => {
        const next = new Set(prev);
        toFetch.forEach((id) => next.add(id));
        return next;
      });

      try {
        const pad = (n: number) => n.toString().padStart(2, '0');
        const rs = rangeStart;
        const dateStr = `${rs.getFullYear()}-${pad(rs.getMonth() + 1)}-${pad(rs.getDate())}`;
        const streamIds = toFetch.map(Number).filter((n) => !isNaN(n));
        const result = await xtreamService.getEpgBatch(streamIds, dateStr);

        setEpgMap((prev) => {
          const next = { ...prev };
          Object.entries(result).forEach(([sid, data]) => {
            next[sid] = buildPrograms(sid, data.epg_listings || [], rangeStart);
          });
          // Channels with no listings still get an empty array so they stop showing a spinner
          toFetch.forEach((id) => {
            if (!(id in next)) next[id] = [];
          });
          epgMapRef.current = next;
          return next;
        });
      } catch (err) {
        console.error('[EPGScreen] EPG fetch error', err);
        setEpgMap((prev) => {
          const next = { ...prev };
          toFetch.forEach((id) => { next[id] = []; });
          epgMapRef.current = next;
          return next;
        });
      } finally {
        setLoadingEpgIds((prev) => {
          const next = new Set(prev);
          toFetch.forEach((id) => next.delete(id));
          return next;
        });
      }
    },
    [rangeStart],
  );

  // ── Load channels on mount ────────────────────────────────────────────
  useEffect(() => {
    if (!isConfigured) return;

    const load = async () => {
      setIsLoadingChannels(true);
      try {
        let streams = liveStreams;
        if (!streams.length) streams = await fetchLiveStreams();

        const ch: Channel[] = streams.map((s: XtreamLiveStream) => ({
          uuid: String(s.stream_id),
          title: s.name || 'Unknown',
          logo: s.stream_icon || '',
        }));
        channelsRef.current = ch;
        setChannels(ch);

        // Pre-fetch first visible batch
        fetchEpgForChannels(ch.slice(0, 15).map((c) => c.uuid));
      } catch (e) {
        console.error('[EPGScreen] channel load error', e);
      } finally {
        setIsLoadingChannels(false);
      }
    };

    load();
  }, [isConfigured, fetchLiveStreams, liveStreams, fetchEpgForChannels]);

  // ── Initialise scrollX to centre "now" ───────────────────────────────
  useEffect(() => {
    if (!viewportWidth) return;
    const initial = clamp(NOW_LEFT - viewportWidth * 0.35, 0, TOTAL_TRACK_WIDTH - viewportWidth);
    setScrollX(initial);
    scrollXRef.current = initial;
  }, [viewportWidth]);

  // ── Helpers ───────────────────────────────────────────────────────────

  const scrollToRow = useCallback((rowIdx: number) => {
    const lh = listHeightRef.current;
    const maxY = Math.max(0, channels.length * CHANNEL_HEIGHT - lh);
    const newY = clamp(
      rowIdx * CHANNEL_HEIGHT - lh * 0.4,
      0,
      maxY,
    );
    setScrollY(newY);
    scrollYRef.current = newY;
  }, [channels.length]);

  /**
   * Returns the index of the first programme that is at least partially
   * visible within the current horizontal viewport.  Falls back to the
   * programme whose midpoint is closest to the viewport centre so we never
   * accidentally land on the chronological first (often a midnight show
   * that is completely off-screen left).
   */
  const findFirstVisibleProgramIdx = useCallback((uuid: string): number => {
    const progs = epgMapRef.current[uuid];
    if (!progs?.length) return 0;
    const sx = scrollXRef.current;
    for (let i = 0; i < progs.length; i++) {
      // Programme has at least some part within [sx, sx + viewportWidth]
      if (progs[i].left + progs[i].width > sx && progs[i].left < sx + viewportWidth) {
        return i;
      }
    }
    // Fallback: closest midpoint to the viewport centre
    const centre = sx + viewportWidth / 2;
    let bestIdx = 0;
    let bestDist = Infinity;
    for (let i = 0; i < progs.length; i++) {
      const dist = Math.abs((progs[i].left + progs[i].width / 2) - centre);
      if (dist < bestDist) { bestDist = dist; bestIdx = i; }
    }
    return bestIdx;
  }, [viewportWidth]);

  /**
   * Returns the index of the currently-airing programme (the one whose
   * time-range straddles NOW_LEFT).  Falls back to findFirstVisibleProgramIdx.
   * Used on first entry into grid mode so focus always lands on what is
   * playing right now rather than the chronological first programme.
   */
  const findNowProgramIdx = useCallback((uuid: string): number => {
    const progs = epgMapRef.current[uuid];
    if (!progs?.length) return 0;
    for (let i = 0; i < progs.length; i++) {
      if (progs[i].left <= NOW_LEFT && progs[i].left + progs[i].width > NOW_LEFT) {
        return i;
      }
    }
    return findFirstVisibleProgramIdx(uuid);
  }, [findFirstVisibleProgramIdx]);

  const scrollToProgram = useCallback(
    (uuid: string, colIdx: number) => {
      const prog = epgMapRef.current[uuid]?.[colIdx];
      if (!prog) return;
      const newX = clamp(
        prog.left + prog.width / 2 - viewportWidth / 2,
        0,
        TOTAL_TRACK_WIDTH - viewportWidth,
      );
      setScrollX(newX);
      scrollXRef.current = newX;
    },
    [viewportWidth],
  );

  // ── TV remote event handler ───────────────────────────────────────────
  useEffect(() => {
    if (!isFocused) return;

    // Always consume the hardware back event so the MainNavigator's back
    // handler never fires (which would erroneously re-open the nav drawer).
    const onBack = () => {
      if (isSidebarActiveRef.current) {
        // Nav sidebar is open → close it and return to the EPG channel column.
        setSidebarActive(false);
        return true;
      }
      if (focusModeRef.current === 'grid') {
        focusModeRef.current = 'sidebar';
        setFocusMode('sidebar');
      } else {
        // Channel column → open the nav sidebar so the user can navigate to
        // another screen (avoids closing the app with no visible escape route).
        setSidebarActive(true);
      }
      return true; // always consume
    };
    const backHandler = BackHandler.addEventListener('hardwareBackPress', onBack);

    const TVHandler: any = TVEventHandler;
    if (!TVHandler) return () => backHandler.remove();

    const listener = (event: { eventType?: string }) => {
      const type = event?.eventType;
      if (!type) return;

      // When the nav sidebar is open, only handle Back/Menu (which closes it).
      // All other navigation events are handled by native focus on the sidebar
      // items; we must not also navigate the EPG rows.
      if (isSidebarActiveRef.current) {
        if (type === 'back' || type === 'menu') {
          setSidebarActive(false);
        }
        return;
      }

      // Keep the nav sidebar suppressed while EPG navigation is active.
      setSidebarActive(false);

      const mode = focusModeRef.current;
      const row = focusedRowRef.current;
      const col = focusedColRef.current;
      const ch = channelsRef.current;
      const totalRows = ch.length;

      // ── Back / Menu ──────────────────────────────────────────────
      if (type === 'back' || type === 'menu') {
        if (mode === 'grid') {
          focusModeRef.current = 'sidebar';
          setFocusMode('sidebar');
        } else {
          // Open the nav sidebar (mirrors the BackHandler logic above).
          setSidebarActive(true);
        }
        return;
      }

      // ── SIDEBAR mode ─────────────────────────────────────────────
      if (mode === 'sidebar') {
        if (type === 'up' || type === 'down') {
          const next = clamp(row + (type === 'down' ? 1 : -1), 0, totalRows - 1);
          if (next !== row) {
            focusedRowRef.current = next;
            setFocusedRow(next);
            scrollToRow(next);
            const uuids = ch
              .slice(Math.max(0, next - 3), next + 10)
              .map((c) => c.uuid);
            fetchEpgForChannels(uuids);
          }
        } else if (type === 'right' || type === 'select') {
          const uuid = ch[row]?.uuid;
          // Prefer the currently-airing programme when first entering the grid
          // so the focused block is always visible and meaningful.
          const nowIdx = uuid ? findNowProgramIdx(uuid) : 0;
          focusedColRef.current = nowIdx;
          setFocusedCol(nowIdx);
          hasManuallyNavigated.current = false;
          focusModeRef.current = 'grid';
          setFocusMode('grid');
          // Scroll the viewport to show the focused programme.
          if (uuid) scrollToProgram(uuid, nowIdx);
        } else if (type === 'left') {
          // Open the nav sidebar so the user can navigate to another screen.
          setSidebarActive(true);
        }
        return;
      }

      // ── GRID mode ────────────────────────────────────────────────

      if (type === 'up' || type === 'down') {
        const next = clamp(row + (type === 'down' ? 1 : -1), 0, totalRows - 1);
        if (next !== row) {
          focusedRowRef.current = next;
          setFocusedRow(next);
          scrollToRow(next);
          const nextUuid = ch[next]?.uuid;
          // Keep the same time position – find the first visible programme in
          // the new row at the CURRENT scrollX (no horizontal scroll jump).
          const visibleIdx = nextUuid ? findFirstVisibleProgramIdx(nextUuid) : 0;
          focusedColRef.current = visibleIdx;
          setFocusedCol(visibleIdx);
          hasManuallyNavigated.current = false;
          // Scroll to ensure the focused programme is actually on-screen.
          if (nextUuid) scrollToProgram(nextUuid, visibleIdx);
          fetchEpgForChannels(
            ch.slice(Math.max(0, next - 3), next + 10).map((c) => c.uuid),
          );
        }
      } else if (type === 'left') {
        const uuid = ch[row]?.uuid;
        const progs = epgMapRef.current[uuid ?? ''] ?? [];
        const next = col - 1;

        if (progs.length > 0 && next >= 0) {
          // Navigate to previous programme
          hasManuallyNavigated.current = true;
          focusedColRef.current = next;
          setFocusedCol(next);
          if (uuid) scrollToProgram(uuid, next);
        } else {
          // No programmes (loading or genuinely empty) OR at the leftmost
          // programme → return to the channel column in sidebar mode.
          focusModeRef.current = 'sidebar';
          setFocusMode('sidebar');
        }
      } else if (type === 'right') {
        const uuid = ch[row]?.uuid;
        const progs = epgMapRef.current[uuid ?? ''] ?? [];

        if (progs.length === 0) {
          // No EPG yet – scroll right to show future time
          const newX = Math.min(
            TOTAL_TRACK_WIDTH - viewportWidth,
            scrollXRef.current + SCROLL_STEP,
          );
          if (newX !== scrollXRef.current) {
            setScrollX(newX);
            scrollXRef.current = newX;
          }
          return;
        }

        const next = clamp(col + 1, 0, progs.length - 1);
        if (next !== col) {
          hasManuallyNavigated.current = true;
          focusedColRef.current = next;
          setFocusedCol(next);
          if (uuid) scrollToProgram(uuid, next);
        }
      }
      // 'select' → could open programme details in a future iteration
    };

    let subscription: { remove?: () => void } | undefined;
    if (typeof TVHandler.addListener === 'function') {
      subscription = TVHandler.addListener(listener);
    } else if (typeof TVHandler === 'function') {
      const instance = new TVHandler();
      instance.enable(null, (_: unknown, event: { eventType?: string }) => listener(event));
      subscription = { remove: () => instance.disable() };
    }

    return () => {
      backHandler.remove();
      subscription?.remove?.();
    };
  }, [
    isFocused,
    isSidebarActive,
    navigation,
    viewportWidth,
    fetchEpgForChannels,
    findFirstVisibleProgramIdx,
    findNowProgramIdx,
    scrollToProgram,
    scrollToRow,
    setSidebarActive,
  ]);

  // ── When EPG arrives for the focused row, snap col to best visible idx ─
  const focusedChannelUuid = channels[focusedRow]?.uuid;
  const focusedChannelEpg = epgMap[focusedChannelUuid ?? ''];
  useEffect(() => {
    // Use the ref for mode check to avoid stale closure issues
    if (!focusedChannelUuid || focusModeRef.current !== 'grid' || !focusedChannelEpg) return;
    // Don't override if the user has already manually navigated in this row
    if (hasManuallyNavigated.current) return;
    const visibleIdx = findFirstVisibleProgramIdx(focusedChannelUuid);
    setFocusedCol(visibleIdx);
    focusedColRef.current = visibleIdx;
    // Scroll to show the newly-snapped programme
    scrollToProgram(focusedChannelUuid, visibleIdx);
  }, [focusedChannelEpg]);

  // (renderChannel, getItemLayout, keyExtractor removed – using windowed view)

  // ── Guard renders ─────────────────────────────────────────────────────
  if (!isConfigured) {
    return (
      <View style={styles.center}>
        <Text style={styles.message}>Please connect to your service in Settings</Text>
      </View>
    );
  }

  if (!isFocused) return null;

  if (isLoadingChannels) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color={colors.primary} />
        <Text style={styles.message}>Loading channels…</Text>
      </View>
    );
  }

  if (!channels.length) {
    return (
      <View style={styles.center}>
        <Text style={styles.message}>No channels available</Text>
      </View>
    );
  }

  // ── Render ────────────────────────────────────────────────────────────
  return (
    <View style={styles.root}>
      {/* ── Header ── */}
      <View style={styles.headerRow}>
        <View style={styles.headerCorner}>
          <Text style={styles.headerCornerText}>EPG</Text>
        </View>
        <TimeRuler rangeStart={rangeStart} scrollX={scrollX} viewportWidth={viewportWidth} />
      </View>

      {/* ── Channel rows (manual windowed view – avoids tvOS FlatList bugs) ── */}
      <View style={styles.channelList}>
        {(() => {
          // Compute visible window at render time so we always render fresh rows
          const lh = listHeightRef.current || (screenHeight - TIME_HEADER_HEIGHT);
          const OVERSCAN = 4;
          const first = Math.max(0, Math.floor(scrollY / CHANNEL_HEIGHT) - OVERSCAN);
          const last = Math.min(
            channels.length - 1,
            Math.ceil((scrollY + lh) / CHANNEL_HEIGHT) + OVERSCAN,
          );
          const isGrid = focusMode === 'grid';

          return (
            <View style={{ transform: [{ translateY: -scrollY }] }}>
              {/* Top spacer for unrendered rows above */}
              {first > 0 && <View style={{ height: first * CHANNEL_HEIGHT }} />}
              {channels.slice(first, last + 1).map((channel, localIdx) => {
                const globalIdx = first + localIdx;
                return (
                  <ChannelRow
                    key={channel.uuid}
                    channel={channel}
                    programs={epgMap[channel.uuid] ?? []}
                    isEpgLoading={loadingEpgIds.has(channel.uuid)}
                    sidebarFocused={!isGrid && globalIdx === focusedRow}
                    focusedProgramIdx={globalIdx === focusedRow ? focusedCol : -1}
                    scrollX={scrollX}
                    viewportWidth={viewportWidth}
                    isCurrentRow={globalIdx === focusedRow}
                    isGridMode={isGrid}
                  />
                );
              })}
            </View>
          );
        })()}
      </View>

      {/* ── Focus capture – released when nav sidebar is open ── */}
      <FocusCapture active={!isSidebarActive} />

      {/* ── Mode indicator ── */}
      {focusMode === 'sidebar' && (
        <View style={styles.sidebarModeBar} pointerEvents="none" />
      )}
      {focusMode === 'grid' && (
        <View style={styles.gridModeIndicator} pointerEvents="none" />
      )}
    </View>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────────
const BORDER = colors.border;
const FOCUS_C = colors.focus;
const NOW_C = '#ec003f';

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: colors.background,
  },

  // Header
  headerRow: {
    height: TIME_HEADER_HEIGHT,
    flexDirection: 'row',
    borderBottomWidth: 1,
    borderBottomColor: BORDER,
    // Must sit above the channel rows which use translateY to scroll vertically
    zIndex: 10,
  },
  headerCorner: {
    width: SIDEBAR_WIDTH,
    justifyContent: 'center',
    alignItems: 'center',
    borderRightWidth: 1,
    borderRightColor: BORDER,
    backgroundColor: colors.backgroundElevated,
  },
  headerCornerText: {
    color: colors.textTertiary,
    fontSize: scaledPixels(13),
    fontWeight: '700',
    letterSpacing: 2,
    textTransform: 'uppercase',
  },

  // Time ruler
  timeRuler: {
    flex: 1,
    height: TIME_HEADER_HEIGHT,
    overflow: 'hidden',
    backgroundColor: colors.backgroundElevated,
    position: 'relative',
  },
  timeMarker: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    alignItems: 'flex-start',
    justifyContent: 'flex-end',
    paddingBottom: scaledPixels(6),
    paddingLeft: scaledPixels(6),
  },
  timeMarkerText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(12),
    fontWeight: '600',
  },
  timeMarkerHalf: {
    color: colors.textTertiary,
    fontWeight: '400',
  },
  timeMarkerTick: {
    position: 'absolute',
    top: 0,
    left: 0,
    width: 1,
    height: TIME_HEADER_HEIGHT,
    backgroundColor: BORDER,
  },
  timeMarkerTickHalf: {
    backgroundColor: colors.divider,
    opacity: 0.5,
  },
  nowTickInRuler: {
    position: 'absolute',
    top: 0,
    width: 2,
    height: TIME_HEADER_HEIGHT,
    backgroundColor: NOW_C,
    opacity: 0.9,
  },

  // Channel rows
  channelList: {
    flex: 1,
    overflow: 'hidden',
  },
  channelRow: {
    height: CHANNEL_HEIGHT,
    flexDirection: 'row',
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.borderLight,
    backgroundColor: colors.backgroundElevated,
    overflow: 'hidden',
  },
  // Highlight the active row in grid mode so the user always sees which row is selected
  channelRowGridActive: {
    backgroundColor: colors.cardElevated,
  },
  sidebarCell: {
    width: SIDEBAR_WIDTH,
    height: CHANNEL_HEIGHT,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: scaledPixels(10),
    borderRightWidth: 1,
    borderRightColor: BORDER,
    borderLeftWidth: scaledPixels(3),
    borderLeftColor: 'transparent',
    backgroundColor: colors.backgroundElevated,
    gap: scaledPixels(8),
  },
  sidebarCellHighlight: {
    backgroundColor: colors.card,
  },
  sidebarCellFocused: {
    backgroundColor: colors.card,
    borderLeftColor: FOCUS_C,
  },
  channelLogo: {
    width: scaledPixels(40),
    height: scaledPixels(40),
  },
  channelTitle: {
    flex: 1,
    color: colors.textSecondary,
    fontSize: scaledPixels(12),
    lineHeight: scaledPixels(16),
  },
  channelTitleFocused: {
    color: colors.text,
    fontWeight: '700',
  },

  // Programme viewport
  programViewport: {
    flex: 1,
    height: CHANNEL_HEIGHT,
    overflow: 'hidden',
    position: 'relative',
  },
  nowBarRow: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    width: 2,
    backgroundColor: NOW_C,
    opacity: 0.5,
    zIndex: 10,
  },

  // Programme blocks
  programBlock: {
    position: 'absolute',
    top: scaledPixels(5),
    height: CHANNEL_HEIGHT - scaledPixels(10),
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.borderLight,
    paddingHorizontal: scaledPixels(10),
    paddingVertical: scaledPixels(4),
    justifyContent: 'center',
    overflow: 'hidden',
  },
  programBlockFocused: {
    backgroundColor: FOCUS_C,
    borderColor: colors.primaryLight,
    borderWidth: scaledPixels(2),
    top: scaledPixels(3),
    height: CHANNEL_HEIGHT - scaledPixels(6),
    zIndex: 5,
  },
  programTitle: {
    color: colors.textSecondary,
    fontSize: scaledPixels(12),
    fontWeight: '500',
  },
  programTitleFocused: {
    color: '#ffffff',
    fontWeight: '700',
    fontSize: scaledPixels(13),
  },
  programTime: {
    color: colors.textTertiary,
    fontSize: scaledPixels(10),
    marginTop: scaledPixels(2),
  },
  programTimeFocused: {
    color: 'rgba(255,255,255,0.8)',
  },

  // EPG row states
  epgLoadingRow: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  noDataRow: {
    flex: 1,
    justifyContent: 'center',
    paddingLeft: scaledPixels(16),
  },
  noDataText: {
    color: colors.textTertiary,
    fontSize: scaledPixels(11),
    fontStyle: 'italic',
  },

  // Full-screen states
  center: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.background,
    gap: scaledPixels(16),
  },
  message: {
    color: colors.textSecondary,
    fontSize: scaledPixels(20),
    textAlign: 'center',
  },

  // Focus capture (invisible, full-screen)
  // Covering the entire screen prevents native TV focus traversal from finding
  // focusable elements in the nav sidebar when pressing Up/Down.
  focusCapture: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    opacity: 0,
  },

  // Sidebar-mode accent bar on the left edge
  sidebarModeBar: {
    position: 'absolute',
    left: 0,
    top: TIME_HEADER_HEIGHT,
    bottom: 0,
    width: scaledPixels(4),
    backgroundColor: FOCUS_C,
    opacity: 0.8,
  },

  // Grid-mode accent bar along the top of the channel list area
  gridModeIndicator: {
    position: 'absolute',
    left: SIDEBAR_WIDTH,
    top: TIME_HEADER_HEIGHT,
    right: 0,
    height: scaledPixels(2),
    backgroundColor: FOCUS_C,
    opacity: 0.6,
  },
});
