import { useEffect, useRef } from 'react';

export type RemoteEvent =
  | 'select'
  | 'playPause'
  | 'left'
  | 'right'
  | 'up'
  | 'down'
  | 'longLeft'
  | 'longRight'
  | 'back'
  | 'fastForward'
  | 'rewind';

type RemoteEventCallback = (event: RemoteEvent) => void;

export function useTVRemoteEvents(callback: RemoteEventCallback) {
  const callbackRef = useRef(callback);
  callbackRef.current = callback;

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      switch (e.key) {
        case 'ArrowLeft':
          callbackRef.current(e.repeat ? 'longLeft' : 'left');
          break;
        case 'ArrowRight':
          callbackRef.current(e.repeat ? 'longRight' : 'right');
          break;
        case 'ArrowUp':
          callbackRef.current('up');
          break;
        case 'ArrowDown':
          callbackRef.current('down');
          break;
        case 'Enter':
          callbackRef.current('select');
          break;
        case ' ':
          e.preventDefault();
          callbackRef.current('playPause');
          break;
        case 'Escape':
          callbackRef.current('back');
          break;
        case 'MediaPlayPause':
          callbackRef.current('playPause');
          break;
        case 'MediaTrackNext':
        case 'MediaFastForward':
          callbackRef.current('fastForward');
          break;
        case 'MediaTrackPrevious':
        case 'MediaRewind':
          callbackRef.current('rewind');
          break;
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, []);
}
