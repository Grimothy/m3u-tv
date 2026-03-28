import { useEffect, useRef } from 'react';
import { TVEventHandler } from 'react-native';

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
    // @ts-expect-error — TVEventHandler constructor is valid in react-native-tvos
    const handler = new TVEventHandler();
    handler.enable(undefined, (_: any, evt: any) => {
      const type: string = evt?.eventType;
      switch (type) {
        case 'select':
          callbackRef.current('select');
          break;
        case 'playPause':
          callbackRef.current('playPause');
          break;
        case 'left':
          callbackRef.current('left');
          break;
        case 'right':
          callbackRef.current('right');
          break;
        case 'up':
          callbackRef.current('up');
          break;
        case 'down':
          callbackRef.current('down');
          break;
        case 'longLeft':
          callbackRef.current('longLeft');
          break;
        case 'longRight':
          callbackRef.current('longRight');
          break;
        case 'fastForward':
          callbackRef.current('fastForward');
          break;
        case 'rewind':
          callbackRef.current('rewind');
          break;
      }
    });

    return () => handler.disable();
  }, []);
}
