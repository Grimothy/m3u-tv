import React, { useCallback, useEffect, useRef, useState } from 'react';
import { useViewer } from '../context/ViewerContext';
import { useXtream } from '../context/XtreamContext';
import {
    View,
    StyleSheet,
    Text,
    Pressable,
    ActivityIndicator,
    Animated,
    TVEventHandler,
    TVFocusGuideView,
    BackHandler,
    Platform,
    Alert,
    ActionSheetIOS,
    NativeSyntheticEvent,
} from 'react-native';
import {
    MpvPlayer,
    MpvPlayerRef,
    MpvLoadEvent,
    MpvProgressEvent,
    MpvBufferEvent,
    MpvErrorEvent,
    MpvTrack,
} from 'react-native-mpv';
import { RootStackScreenProps } from '../navigation/types';
import { colors } from '../theme';
import { Icon } from '../components/Icon';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable, FocusablePressableRef } from '../components/FocusablePressable';
import { epgService } from '../services/EpgService';

const OVERLAY_TIMEOUT = 8000;
const SEEK_STEP = 10;
const TIMELINE_SEEK_STEP = 30;
const LOADING_TIMEOUT_MS = 20_000;
const PROGRESS_INTERVAL_MS = 10_000;
const USER_AGENT =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36';

type PlayerTrack = { id: number; name: string; language?: string };

function formatTime(seconds: number): string {
    const safeSeconds = Number.isFinite(seconds) ? seconds : 0;
    const s = Math.max(0, Math.floor(safeSeconds));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const sec = s % 60;
    const pad = (n: number) => n.toString().padStart(2, '0');
    return h > 0 ? `${h}:${pad(m)}:${pad(sec)}` : `${m}:${pad(sec)}`;
}

function showNativeSelect(
    title: string,
    options: string[],
    selectedIndex: number,
    onPick: (index: number) => void,
) {
    if (Platform.OS === 'ios' && !Platform.isTV) {
        ActionSheetIOS.showActionSheetWithOptions(
            {
                title,
                options: [...options, 'Cancel'],
                cancelButtonIndex: options.length,
            },
            (buttonIndex) => {
                if (buttonIndex < options.length) {
                    onPick(buttonIndex);
                }
            },
        );
        return;
    }

    Alert.alert(
        title,
        undefined,
        [
            ...options.map((option, index) => ({
                text: index === selectedIndex ? `\u2713 ${option}` : option,
                onPress: () => onPick(index),
            })),
            { text: 'Cancel', style: 'cancel' as const },
        ],
        { cancelable: true },
    );
}

const isTV = Platform.isTV;
const isTVOS = Platform.OS === 'ios' && isTV;

const FocusContainer = isTVOS
    ? ({ style, children }: { style?: any; children: React.ReactNode }) => (
          <TVFocusGuideView style={style} autoFocus>
              {children}
          </TVFocusGuideView>
      )
    : ({ style, children }: { style?: any; children: React.ReactNode }) => (
          <View style={style}>{children}</View>
      );

export const PlayerScreen = ({ route, navigation }: RootStackScreenProps<'Player'>) => {
    const { streamUrl, title, type, streamId, seriesId, seasonNumber, startPosition, epgChannelId } =
        route.params;
    const isLive = type === 'live';

    const { isM3UEditor } = useXtream();
    const { activeViewer, updateProgress } = useViewer();

    const mpvRef = useRef<MpvPlayerRef>(null);

    const playButtonRef = useRef<FocusablePressableRef>(null);
    const rewindButtonRef = useRef<FocusablePressableRef>(null);
    const forwardButtonRef = useRef<FocusablePressableRef>(null);
    const timelineRef = useRef<FocusablePressableRef>(null);
    const timelineFocusedRef = useRef(false);
    const audioButtonRef = useRef<FocusablePressableRef>(null);
    const subtitleButtonRef = useRef<FocusablePressableRef>(null);
    const backButtonRef = useRef<FocusablePressableRef>(null);

    const [epgCurrent, setEpgCurrent] = useState<{ title: string; progress: number } | null>(null);
    const [epgNext, setEpgNext] = useState<string | null>(null);

    const [isLoading, setIsLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [paused, setPaused] = useState(false);
    const [currentTime, setCurrentTime] = useState(0);
    const [duration, setDuration] = useState(0);

    const [audioTracks, setAudioTracks] = useState<PlayerTrack[]>([]);
    const [textTracks, setTextTracks] = useState<PlayerTrack[]>([]);
    const [selectedAudioTrack, setSelectedAudioTrack] = useState<number>(-1);
    const [selectedTextTrack, setSelectedTextTrack] = useState<number>(-1);

    const seekingRef = useRef(false);
    const seekLockoutTimer = useRef<ReturnType<typeof setTimeout>>(undefined);
    const exitGuardRef = useRef(false);
    const tracksLoadedRef = useRef(false);
    const loadingTimerRef = useRef<ReturnType<typeof setTimeout>>(undefined);

    const currentTimeRef = useRef(currentTime);
    const durationRef = useRef(duration);

    useEffect(() => {
        currentTimeRef.current = currentTime;
    }, [currentTime]);
    useEffect(() => {
        durationRef.current = duration;
    }, [duration]);

    // ── Loading timeout ──────────────────────────────────────────
    useEffect(() => {
        if (isLoading && !error) {
            loadingTimerRef.current = setTimeout(() => {
                if (isLoading) {
                    setIsLoading(false);
                    setError(
                        'Stream loading timed out. The server may be unreachable or the stream URL is invalid.',
                    );
                }
            }, LOADING_TIMEOUT_MS);
        } else {
            clearTimeout(loadingTimerRef.current);
        }
        return () => clearTimeout(loadingTimerRef.current);
    }, [isLoading, error]);

    // ── Watch progress tracking ──────────────────────────────────
    useEffect(() => {
        if (!isM3UEditor || !activeViewer || !streamId) return;

        if (isLive) {
            updateProgress({ content_type: 'live', stream_id: streamId });
            return;
        }

        const interval = setInterval(() => {
            updateProgress({
                content_type: type === 'series' ? 'episode' : 'vod',
                stream_id: streamId,
                position_seconds: Math.floor(currentTimeRef.current),
                duration_seconds: durationRef.current > 0 ? Math.floor(durationRef.current) : undefined,
                series_id: seriesId,
                season_number: seasonNumber,
            });
        }, PROGRESS_INTERVAL_MS);

        return () => {
            clearInterval(interval);
            if (currentTimeRef.current > 0) {
                updateProgress({
                    content_type: type === 'series' ? 'episode' : 'vod',
                    stream_id: streamId,
                    position_seconds: Math.floor(currentTimeRef.current),
                    duration_seconds: durationRef.current > 0 ? Math.floor(durationRef.current) : undefined,
                    series_id: seriesId,
                    season_number: seasonNumber,
                });
            }
        };
    }, [isM3UEditor, activeViewer, streamId, isLive, type, seriesId, seasonNumber]);

    // ── Fetch EPG data for live channel ──────────────────────────
    useEffect(() => {
        if (!isLive || !streamId) return;

        let interval: ReturnType<typeof setInterval>;
        let cancelled = false;

        const updateEpg = async () => {
            const data = await epgService.getCurrentAndNextAsync(epgChannelId || '', streamId);
            if (cancelled) return;

            if (!data) {
                setEpgCurrent(null);
                setEpgNext(null);
                return;
            }

            setEpgCurrent({ title: data.currentTitle, progress: data.currentProgress });
            setEpgNext(data.nextTitle);
        };

        updateEpg();
        interval = setInterval(updateEpg, 30000);

        return () => {
            cancelled = true;
            clearInterval(interval);
        };
    }, [isLive, streamId, epgChannelId]);

    // ── Overlay animation ────────────────────────────────────────
    const [overlayVisible, setOverlayVisible] = useState(true);
    const fadeAnim = useRef(new Animated.Value(1)).current;
    const hideTimer = useRef<ReturnType<typeof setTimeout>>(undefined);
    const overlayVisibleRef = useRef(overlayVisible);

    useEffect(() => {
        overlayVisibleRef.current = overlayVisible;
    }, [overlayVisible]);

    const hideOverlayAnim = useCallback(() => {
        Animated.timing(fadeAnim, {
            toValue: 0,
            duration: 300,
            useNativeDriver: true,
        }).start(() => {
            setOverlayVisible(false);
        });
    }, [fadeAnim]);

    const resetHideTimer = useCallback(() => {
        clearTimeout(hideTimer.current);
        hideTimer.current = setTimeout(hideOverlayAnim, OVERLAY_TIMEOUT);
    }, [hideOverlayAnim]);

    const showOverlay = useCallback(() => {
        setOverlayVisible(true);
        fadeAnim.setValue(1);
        resetHideTimer();
        setTimeout(() => {
            playButtonRef.current?.focus();
        }, 150);
    }, [fadeAnim, resetHideTimer]);

    useEffect(() => {
        resetHideTimer();
        if (overlayVisible) {
            setTimeout(() => {
                playButtonRef.current?.focus();
            }, 150);
        }
        return () => clearTimeout(hideTimer.current);
    }, [overlayVisible, resetHideTimer]);

    // ── Navigation helpers ───────────────────────────────────────
    const goBackSafe = useCallback(() => {
        if (exitGuardRef.current) return;
        exitGuardRef.current = true;
        navigation.goBack();
    }, [navigation]);

    const doSeekTo = useCallback(
        (targetSeconds: number) => {
            const dur = durationRef.current;
            if (dur <= 0 || isLive) return;

            const target = Math.max(0, Math.min(targetSeconds, dur));
            seekingRef.current = true;
            setCurrentTime(target);

            if (seekLockoutTimer.current) {
                clearTimeout(seekLockoutTimer.current);
            }
            seekLockoutTimer.current = setTimeout(() => {
                seekingRef.current = false;
            }, 1500);

            mpvRef.current?.seekTo(target);
        },
        [isLive],
    );

    const doSeek = useCallback(
        (offset: number) => {
            doSeekTo(currentTimeRef.current + offset);
        },
        [doSeekTo],
    );

    const doTogglePlayPause = useCallback(() => {
        setPaused((prev) => !prev);
    }, []);

    // ── Track selectors ──────────────────────────────────────────
    const openAudioSelector = useCallback(() => {
        if (audioTracks.length === 0) return;

        const options = ['Disable', ...audioTracks.map((track) => track.name || `Track ${track.id}`)];
        const selectedIndex =
            selectedAudioTrack === -1
                ? 0
                : audioTracks.findIndex((track) => track.id === selectedAudioTrack) + 1;

        showNativeSelect('Audio Track', options, selectedIndex < 0 ? 0 : selectedIndex, (index) => {
            const newTrackId = index === 0 ? -1 : audioTracks[index - 1].id;
            setSelectedAudioTrack(newTrackId);
            mpvRef.current?.setAudioTrack(newTrackId);
            resetHideTimer();
        });
    }, [audioTracks, selectedAudioTrack, resetHideTimer]);

    const openSubtitleSelector = useCallback(() => {
        const options = ['Off', ...textTracks.map((track) => track.name || `Track ${track.id}`)];
        const selectedIndex =
            selectedTextTrack === -1
                ? 0
                : Math.max(
                      0,
                      textTracks.findIndex((track) => track.id === selectedTextTrack) + 1,
                  );

        showNativeSelect('Subtitle Track', options, selectedIndex, (index) => {
            const newTrackId = index === 0 ? -1 : textTracks[index - 1]?.id ?? -1;
            setSelectedTextTrack(newTrackId);
            mpvRef.current?.setSubtitleTrack(newTrackId);
            resetHideTimer();
        });
    }, [textTracks, selectedTextTrack, resetHideTimer]);

    // ── mpv event handlers ───────────────────────────────────────
    const handleMpvLoad = useCallback((event: NativeSyntheticEvent<MpvLoadEvent>) => {
        const data = event.nativeEvent;
        setError(null);
        setIsLoading(false);
        const dur = data.duration || 0;
        setDuration(dur);

        if (!tracksLoadedRef.current) {
            const audio = (data.audioTracks ?? []).filter((t: MpvTrack) => t.id >= 0);
            const text = (data.textTracks ?? []).filter((t: MpvTrack) => t.id >= 0);
            if (audio.length > 0 || text.length > 0) {
                tracksLoadedRef.current = true;
                setAudioTracks(audio);
                setTextTracks(text);
            }
        }
    }, []);

    const handleMpvProgress = useCallback(
        (event: NativeSyntheticEvent<MpvProgressEvent>) => {
            const data = event.nativeEvent;
            if (isLoading) setIsLoading(false);
            if (error) setError(null);

            if (!seekingRef.current) {
                if (data.duration > 0 && data.duration !== durationRef.current) {
                    setDuration(data.duration);
                }
                setCurrentTime(data.currentTime);
            }
        },
        [isLoading, error],
    );

    const handleMpvBuffer = useCallback((event: NativeSyntheticEvent<MpvBufferEvent>) => {
        const { isBuffering } = event.nativeEvent;
        if (isBuffering) {
            setIsLoading(true);
            setError(null);
        } else {
            setIsLoading(false);
        }
    }, []);

    const handleMpvError = useCallback((event: NativeSyntheticEvent<MpvErrorEvent>) => {
        const { error: errorMsg } = event.nativeEvent;
        console.error('[PlayerScreen] mpv playback error', errorMsg);
        setIsLoading(false);
        setError(errorMsg || 'Unknown playback error');
    }, []);

    const handleMpvEnd = useCallback(() => {
        goBackSafe();
    }, [goBackSafe]);

    const handleMpvTracksChanged = useCallback(
        (
            event: NativeSyntheticEvent<{
                audioTracks: MpvTrack[];
                textTracks: MpvTrack[];
            }>,
        ) => {
            const data = event.nativeEvent;
            const audio = (data.audioTracks ?? []).filter((t: MpvTrack) => t.id >= 0);
            const text = (data.textTracks ?? []).filter((t: MpvTrack) => t.id >= 0);
            if (audio.length > 0) setAudioTracks(audio);
            if (text.length > 0) setTextTracks(text);
        },
        [],
    );

    // ── TV remote & back button handling ─────────────────────────
    useEffect(() => {
        const backAction = () => {
            if (overlayVisibleRef.current) {
                hideOverlayAnim();
                return true;
            }
            goBackSafe();
            return true;
        };

        const backHandler = BackHandler.addEventListener('hardwareBackPress', backAction);
        const TVHandler: any = TVEventHandler;
        if (!TVHandler) {
            return () => {
                backHandler.remove();
            };
        }

        const listener = (event: { eventType?: string }) => {
            if (!event?.eventType) return;

            if (!overlayVisibleRef.current) {
                if (event.eventType === 'back' || event.eventType === 'menu') {
                    goBackSafe();
                    return;
                }
                showOverlay();
                return;
            }

            if (event.eventType === 'back' || event.eventType === 'menu') {
                hideOverlayAnim();
                return;
            }

            if (timelineFocusedRef.current) {
                if (event.eventType === 'left') {
                    doSeek(-SEEK_STEP);
                    resetHideTimer();
                    return;
                }
                if (event.eventType === 'right') {
                    doSeek(SEEK_STEP);
                    resetHideTimer();
                    return;
                }
                if (event.eventType === 'longLeft') {
                    doSeek(-TIMELINE_SEEK_STEP);
                    resetHideTimer();
                    return;
                }
                if (event.eventType === 'longRight') {
                    doSeek(TIMELINE_SEEK_STEP);
                    resetHideTimer();
                    return;
                }
            }

            if (event.eventType === 'playPause') {
                doTogglePlayPause();
                resetHideTimer();
                return;
            }
            if (event.eventType === 'fastForward') {
                doSeek(SEEK_STEP);
                resetHideTimer();
                return;
            }
            if (event.eventType === 'rewind') {
                doSeek(-SEEK_STEP);
                resetHideTimer();
                return;
            }

            resetHideTimer();
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
    }, [doSeek, doTogglePlayPause, goBackSafe, hideOverlayAnim, resetHideTimer, showOverlay]);

    useEffect(() => {
        return () => {
            if (seekLockoutTimer.current) clearTimeout(seekLockoutTimer.current);
            mpvRef.current?.stop();
        };
    }, []);

    // ── Computed values ──────────────────────────────────────────
    const canSeek = !isLive && duration > 0;
    const progress = canSeek ? (currentTime / duration) * 100 : 0;
    const selectedAudioLabel =
        selectedAudioTrack === -1
            ? 'Disabled'
            : (audioTracks.find((track) => track.id === selectedAudioTrack)?.name ?? 'Select');
    const selectedSubtitleLabel =
        selectedTextTrack === -1
            ? 'Off'
            : (textTracks.find((track) => track.id === selectedTextTrack)?.name ?? 'Select');

    // ── Render ───────────────────────────────────────────────────
    return (
        <View style={styles.container}>
            <View style={StyleSheet.absoluteFill} pointerEvents="none">
                <MpvPlayer
                    ref={mpvRef}
                    uri={streamUrl}
                    userAgent={USER_AGENT}
                    paused={paused}
                    startPosition={startPosition ?? 0}
                    style={styles.player}
                    onMpvLoad={handleMpvLoad}
                    onMpvProgress={handleMpvProgress}
                    onMpvBuffer={handleMpvBuffer}
                    onMpvError={handleMpvError}
                    onMpvEnd={handleMpvEnd}
                    onMpvTracksChanged={handleMpvTracksChanged}
                />
            </View>

            {isLoading && !error && (
                <View style={styles.centerOverlay} pointerEvents="none">
                    <ActivityIndicator color="#ffffff" size="large" />
                    <Text style={styles.loadingText}>Loading stream...</Text>
                    <Text style={styles.loadingSubtext}>Powered by mpv</Text>
                </View>
            )}

            {error && (
                <View style={styles.centerOverlay}>
                    <Text style={styles.errorTitle}>Playback error</Text>
                    <Text style={styles.errorText} numberOfLines={6}>
                        {error}
                    </Text>
                </View>
            )}

            {!overlayVisible && (
                <Pressable
                    style={StyleSheet.absoluteFill}
                    focusable
                    onPress={showOverlay}
                    onFocus={showOverlay}
                />
            )}

            <Animated.View
                style={[styles.overlay, { opacity: fadeAnim }]}
                pointerEvents={overlayVisible ? 'auto' : 'none'}
            >
                <FocusContainer style={styles.overlayInner}>
                    {/* Header: back button + title + EPG */}
                    <View style={styles.header}>
                        <FocusablePressable
                            ref={backButtonRef}
                            onSelect={goBackSafe}
                            onFocus={resetHideTimer}
                            style={({ isFocused }) => [
                                styles.backButton,
                                isFocused && styles.backButtonFocused,
                            ]}
                        >
                            <Icon name="ArrowLeft" size={scaledPixels(24)} color={colors.text} />
                        </FocusablePressable>
                        <View style={styles.headerInfo}>
                            <Text style={styles.title} numberOfLines={1}>
                                {title}
                            </Text>
                            {isLive && epgCurrent && (
                                <View style={styles.epgInfoRow}>
                                    <View style={styles.epgCurrentRow}>
                                        <View style={styles.epgLiveBadge}>
                                            <Text style={styles.epgLiveBadgeText}>LIVE</Text>
                                        </View>
                                        <Text style={styles.epgCurrentTitle} numberOfLines={1}>
                                            {epgCurrent.title}
                                        </Text>
                                    </View>
                                    <View style={styles.epgProgressBg}>
                                        <View
                                            style={[
                                                styles.epgProgressFill,
                                                {
                                                    width: `${Math.round(epgCurrent.progress * 100)}%`,
                                                },
                                            ]}
                                        />
                                    </View>
                                    {epgNext && (
                                        <Text style={styles.epgNextText} numberOfLines={1}>
                                            Next: {epgNext}
                                        </Text>
                                    )}
                                </View>
                            )}
                        </View>
                    </View>

                    {/* Controls bar */}
                    <FocusContainer style={styles.controlsBar}>
                        {canSeek && (
                            <FocusablePressable
                                ref={timelineRef}
                                onFocus={() => {
                                    timelineFocusedRef.current = true;
                                    resetHideTimer();
                                }}
                                onBlur={() => {
                                    timelineFocusedRef.current = false;
                                }}
                                style={({ isFocused }) => [
                                    styles.progressContainer,
                                    isFocused && styles.progressContainerFocused,
                                ]}
                            >
                                {({ isFocused }) => (
                                    <>
                                        <Text style={styles.timeText}>{formatTime(currentTime)}</Text>
                                        <View
                                            style={[
                                                styles.progressTrack,
                                                isFocused && styles.progressTrackFocused,
                                            ]}
                                        >
                                            <View
                                                style={[styles.progressFill, { width: `${progress}%` }]}
                                            />
                                            {isFocused && (
                                                <View
                                                    style={[
                                                        styles.progressThumb,
                                                        { left: `${progress}%` },
                                                    ]}
                                                />
                                            )}
                                        </View>
                                        <Text style={styles.timeText}>{formatTime(duration)}</Text>
                                    </>
                                )}
                            </FocusablePressable>
                        )}

                        <View style={styles.controlsRow}>
                            <FocusablePressable
                                ref={playButtonRef}
                                onSelect={doTogglePlayPause}
                                onFocus={resetHideTimer}
                                style={({ isFocused }) => [
                                    styles.controlButton,
                                    isFocused && styles.controlButtonFocused,
                                ]}
                            >
                                <Icon
                                    name={paused ? 'Play' : 'Pause'}
                                    size={scaledPixels(22)}
                                    color={colors.text}
                                />
                            </FocusablePressable>

                            {!isLive && (
                                <FocusablePressable
                                    ref={rewindButtonRef}
                                    onSelect={() => doSeek(-SEEK_STEP)}
                                    onFocus={resetHideTimer}
                                    style={({ isFocused }) => [
                                        styles.controlButton,
                                        isFocused && styles.controlButtonFocused,
                                    ]}
                                >
                                    <Icon
                                        name="SkipBack"
                                        size={scaledPixels(22)}
                                        color={colors.text}
                                    />
                                </FocusablePressable>
                            )}

                            {!isLive && (
                                <FocusablePressable
                                    ref={forwardButtonRef}
                                    onSelect={() => doSeek(SEEK_STEP)}
                                    onFocus={resetHideTimer}
                                    style={({ isFocused }) => [
                                        styles.controlButton,
                                        isFocused && styles.controlButtonFocused,
                                    ]}
                                >
                                    <Icon
                                        name="SkipForward"
                                        size={scaledPixels(22)}
                                        color={colors.text}
                                    />
                                </FocusablePressable>
                            )}

                            <View style={styles.controlsDivider} />

                            <FocusablePressable
                                ref={audioButtonRef}
                                onSelect={openAudioSelector}
                                onFocus={resetHideTimer}
                                style={({ isFocused }) => [
                                    styles.trackButton,
                                    isFocused && styles.controlButtonFocused,
                                ]}
                            >
                                <Icon
                                    name="Languages"
                                    size={scaledPixels(16)}
                                    color={colors.text}
                                />
                                <Text style={styles.trackButtonText} numberOfLines={1}>
                                    {selectedAudioLabel}
                                </Text>
                            </FocusablePressable>

                            <FocusablePressable
                                ref={subtitleButtonRef}
                                onSelect={openSubtitleSelector}
                                onFocus={resetHideTimer}
                                style={({ isFocused }) => [
                                    styles.trackButton,
                                    isFocused && styles.controlButtonFocused,
                                ]}
                            >
                                <Icon
                                    name="Captions"
                                    size={scaledPixels(16)}
                                    color={colors.text}
                                />
                                <Text style={styles.trackButtonText} numberOfLines={1}>
                                    {selectedSubtitleLabel}
                                </Text>
                            </FocusablePressable>
                        </View>
                    </FocusContainer>
                </FocusContainer>
            </Animated.View>
        </View>
    );
};

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: '#000',
    },
    player: {
        flex: 1,
    },
    centerOverlay: {
        ...StyleSheet.absoluteFillObject,
        justifyContent: 'center',
        alignItems: 'center',
        paddingHorizontal: scaledPixels(24),
        backgroundColor: 'rgba(0,0,0,0.35)',
    },
    loadingText: {
        marginTop: scaledPixels(12),
        color: '#ffffff',
        fontSize: scaledPixels(16),
    },
    loadingSubtext: {
        marginTop: scaledPixels(4),
        color: '#ffffff',
        fontSize: scaledPixels(12),
        opacity: 0.8,
    },
    errorTitle: {
        color: '#ffffff',
        fontSize: scaledPixels(18),
        fontWeight: '700',
        marginBottom: scaledPixels(8),
    },
    errorText: {
        color: '#ffffff',
        fontSize: scaledPixels(14),
        textAlign: 'center',
    },
    overlay: {
        ...StyleSheet.absoluteFillObject,
        padding: scaledPixels(40),
    },
    overlayInner: {
        flex: 1,
        justifyContent: 'flex-end',
    },
    header: {
        flexDirection: 'row',
        alignItems: 'flex-start',
        gap: scaledPixels(12),
        marginBottom: scaledPixels(16),
    },
    backButton: {
        padding: scaledPixels(10),
        borderRadius: scaledPixels(50),
        backgroundColor: 'rgba(0,0,0,0.5)',
        borderWidth: 2,
        borderColor: 'transparent',
    },
    backButtonFocused: {
        backgroundColor: colors.primary,
        borderColor: colors.primary,
    },
    headerInfo: {
        flex: 1,
    },
    title: {
        color: colors.text,
        fontSize: scaledPixels(32),
        fontWeight: 'bold',
        textShadowColor: 'black',
        textShadowOffset: { width: 1, height: 1 },
        textShadowRadius: 5,
    },
    epgInfoRow: {
        marginTop: scaledPixels(8),
        gap: scaledPixels(4),
    },
    epgCurrentRow: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: scaledPixels(8),
    },
    epgLiveBadge: {
        backgroundColor: colors.primary,
        paddingHorizontal: scaledPixels(8),
        paddingVertical: scaledPixels(2),
        borderRadius: scaledPixels(4),
    },
    epgLiveBadgeText: {
        color: '#ffffff',
        fontSize: scaledPixels(11),
        fontWeight: '700',
    },
    epgCurrentTitle: {
        flex: 1,
        color: 'rgba(255,255,255,0.9)',
        fontSize: scaledPixels(18),
        textShadowColor: 'black',
        textShadowOffset: { width: 1, height: 1 },
        textShadowRadius: 3,
    },
    epgProgressBg: {
        height: scaledPixels(3),
        borderRadius: scaledPixels(2),
        backgroundColor: 'rgba(255,255,255,0.2)',
        overflow: 'hidden',
        maxWidth: scaledPixels(400),
    },
    epgProgressFill: {
        height: '100%',
        borderRadius: scaledPixels(2),
        backgroundColor: colors.primary,
    },
    epgNextText: {
        color: 'rgba(255,255,255,0.75)',
        fontSize: scaledPixels(15),
        textShadowColor: 'black',
        textShadowOffset: { width: 1, height: 1 },
        textShadowRadius: 4,
    },
    controlsBar: {
        backgroundColor: 'rgba(0,0,0,0.7)',
        borderRadius: scaledPixels(16),
        paddingHorizontal: scaledPixels(24),
        paddingVertical: scaledPixels(16),
        gap: scaledPixels(12),
    },
    progressContainer: {
        flexDirection: 'row',
        alignItems: 'center',
        borderRadius: scaledPixels(8),
        paddingVertical: scaledPixels(8),
        paddingHorizontal: scaledPixels(4),
    },
    progressContainerFocused: {
        backgroundColor: 'rgba(255,255,255,0.05)',
    },
    progressTrack: {
        flex: 1,
        height: scaledPixels(6),
        backgroundColor: 'rgba(255,255,255,0.3)',
        borderRadius: scaledPixels(3),
        marginHorizontal: scaledPixels(12),
    },
    progressTrackFocused: {
        height: scaledPixels(10),
        borderRadius: scaledPixels(5),
        backgroundColor: 'rgba(255,255,255,0.4)',
    },
    progressFill: {
        height: '100%',
        backgroundColor: colors.primary,
        borderRadius: scaledPixels(5),
    },
    progressThumb: {
        position: 'absolute',
        top: '50%',
        width: scaledPixels(18),
        height: scaledPixels(18),
        borderRadius: scaledPixels(9),
        backgroundColor: colors.primary,
        borderWidth: scaledPixels(2),
        borderColor: '#fff',
        marginLeft: -scaledPixels(9),
        marginTop: -scaledPixels(9),
    },
    timeText: {
        color: colors.textSecondary,
        fontSize: scaledPixels(14),
        fontVariant: ['tabular-nums'],
        minWidth: scaledPixels(60),
        textAlign: 'center',
    },
    controlsRow: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: scaledPixels(8),
    },
    controlButton: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'center',
        paddingHorizontal: scaledPixels(14),
        paddingVertical: scaledPixels(10),
        borderRadius: scaledPixels(8),
        backgroundColor: 'rgba(255,255,255,0.1)',
    },
    controlButtonFocused: {
        backgroundColor: colors.primary,
    },
    controlsDivider: {
        width: 1,
        height: scaledPixels(20),
        backgroundColor: 'rgba(255,255,255,0.2)',
        marginHorizontal: scaledPixels(4),
    },
    trackButton: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: scaledPixels(6),
        paddingHorizontal: scaledPixels(12),
        paddingVertical: scaledPixels(10),
        borderRadius: scaledPixels(8),
        backgroundColor: 'rgba(255,255,255,0.1)',
    },
    trackButtonText: {
        color: colors.text,
        fontSize: scaledPixels(13),
        fontWeight: '600',
    },
});
