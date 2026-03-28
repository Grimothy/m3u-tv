import { Dimensions } from 'react-native';

const BASE_WIDTH = 1920;

export function scaledPixels(size: number): number {
  const { width } = Dimensions.get('window');
  return Math.round(size * (width / BASE_WIDTH));
}
