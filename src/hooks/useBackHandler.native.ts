import { useEffect, useRef } from 'react';
import { BackHandler } from 'react-native';

export function useBackHandler(handler: () => boolean) {
  const handlerRef = useRef(handler);
  handlerRef.current = handler;

  useEffect(() => {
    const subscription = BackHandler.addEventListener('hardwareBackPress', () => {
      return handlerRef.current();
    });
    return () => subscription.remove();
  }, []);
}
