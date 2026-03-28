import React from 'react';
import { View, StyleProp, ViewStyle } from 'react-native';

interface FocusGuideProps {
  style?: StyleProp<ViewStyle>;
  autoFocus?: boolean;
  trapFocusLeft?: boolean;
  trapFocusRight?: boolean;
  children: React.ReactNode;
}

export function FocusGuide({ style, children }: FocusGuideProps) {
  return <View style={style}>{children}</View>;
}
