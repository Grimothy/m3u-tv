import { StyleProp, ViewStyle } from 'react-native';

type StyleType = StyleProp<ViewStyle> | ((props: { isFocused: boolean }) => StyleProp<ViewStyle>);

export type FocusablePressableRef = {
  focus: () => void;
  getNodeHandle: () => number | null;
};

export interface FocusablePressableProps {
  onSelect?: () => void;
  onLongPress?: () => void;
  onFocus?: () => void;
  onBlur?: () => void;
  preferredFocus?: boolean;
  focusable?: boolean;
  /** TV-only: native tag of the element above to guide D-pad focus */
  nextFocusUp?: number;
  /** TV-only: native tag of the element below */
  nextFocusDown?: number;
  /** TV-only: native tag of the element to the left */
  nextFocusLeft?: number;
  /** TV-only: native tag of the element to the right */
  nextFocusRight?: number;
  children: React.ReactNode | ((props: { isFocused: boolean }) => React.ReactNode);
  style?: StyleType;
}
