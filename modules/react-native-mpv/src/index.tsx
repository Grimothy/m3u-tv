import React, { forwardRef, useCallback, useImperativeHandle, useRef } from 'react';
import {
    requireNativeComponent,
    UIManager,
    findNodeHandle,
    ViewStyle,
    StyleProp,
    Platform,
    NativeSyntheticEvent,
} from 'react-native';

// ── Types ────────────────────────────────────────────────────────

export interface MpvTrack {
    id: number;
    name: string;
    language?: string;
}

export interface MpvLoadEvent {
    duration: number;
    audioTracks?: MpvTrack[];
    textTracks?: MpvTrack[];
}

export interface MpvProgressEvent {
    currentTime: number;
    duration: number;
}

export interface MpvBufferEvent {
    isBuffering: boolean;
}

export interface MpvErrorEvent {
    error: string;
}

export interface MpvPlayerRef {
    seekTo: (seconds: number) => void;
    seekRelative: (seconds: number) => void;
    setAudioTrack: (trackId: number) => void;
    setSubtitleTrack: (trackId: number) => void;
    stop: () => void;
}

interface MpvPlayerProps {
    uri: string;
    userAgent?: string;
    paused?: boolean;
    startPosition?: number;
    style?: StyleProp<ViewStyle>;
    onMpvLoad?: (event: NativeSyntheticEvent<MpvLoadEvent>) => void;
    onMpvProgress?: (event: NativeSyntheticEvent<MpvProgressEvent>) => void;
    onMpvBuffer?: (event: NativeSyntheticEvent<MpvBufferEvent>) => void;
    onMpvError?: (event: NativeSyntheticEvent<MpvErrorEvent>) => void;
    onMpvEnd?: (event: NativeSyntheticEvent<Record<string, never>>) => void;
    onMpvTracksChanged?: (event: NativeSyntheticEvent<{ audioTracks: MpvTrack[]; textTracks: MpvTrack[] }>) => void;
}

// ── Native component ─────────────────────────────────────────────

const COMPONENT_NAME = 'MpvPlayerView';

const NativeMpvView = requireNativeComponent<MpvPlayerProps>(COMPONENT_NAME);

function dispatchCommand(ref: React.RefObject<any>, command: string, args: any[] = []) {
    const handle = findNodeHandle(ref.current);
    if (handle == null) return;

    if (Platform.OS === 'ios') {
        UIManager.dispatchViewManagerCommand(handle, command, args);
    } else {
        UIManager.dispatchViewManagerCommand(
            handle,
            UIManager.getViewManagerConfig(COMPONENT_NAME)?.Commands?.[command] ?? command,
            args,
        );
    }
}

// ── Exported component ───────────────────────────────────────────

export const MpvPlayer = forwardRef<MpvPlayerRef, MpvPlayerProps>((props, ref) => {
    const nativeRef = useRef(null);

    const seekTo = useCallback((seconds: number) => {
        dispatchCommand(nativeRef, 'seekTo', [seconds]);
    }, []);

    const seekRelative = useCallback((seconds: number) => {
        dispatchCommand(nativeRef, 'seekRelative', [seconds]);
    }, []);

    const setAudioTrack = useCallback((trackId: number) => {
        dispatchCommand(nativeRef, 'setAudioTrack', [trackId]);
    }, []);

    const setSubtitleTrack = useCallback((trackId: number) => {
        dispatchCommand(nativeRef, 'setSubtitleTrack', [trackId]);
    }, []);

    const stop = useCallback(() => {
        dispatchCommand(nativeRef, 'stop', []);
    }, []);

    useImperativeHandle(ref, () => ({
        seekTo,
        seekRelative,
        setAudioTrack,
        setSubtitleTrack,
        stop,
    }));

    return <NativeMpvView ref={nativeRef} {...props} />;
});

MpvPlayer.displayName = 'MpvPlayer';
