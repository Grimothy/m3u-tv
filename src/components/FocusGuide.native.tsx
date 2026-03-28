import React from 'react';
import { View, TVFocusGuideView, Platform, StyleProp, ViewStyle } from 'react-native';

interface FocusGuideProps {
  style?: StyleProp<ViewStyle>;
  autoFocus?: boolean;
  trapFocusLeft?: boolean;
  trapFocusRight?: boolean;
  children: React.ReactNode;
}

const isTVOS = Platform.OS === 'ios' && Platform.isTV;

export function FocusGuide({ style, autoFocus, trapFocusLeft, trapFocusRight, children }: FocusGuideProps) {
  if (isTVOS) {
    return (
      <TVFocusGuideView
        style={style}
        autoFocus={autoFocus}
        trapFocusLeft={trapFocusLeft}
        trapFocusRight={trapFocusRight}
      >
        {children}
      </TVFocusGuideView>
    );
  }

  return <View style={style}>{children}</View>;
}
