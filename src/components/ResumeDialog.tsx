import React from 'react';
import { View, Text, Modal, StyleSheet } from 'react-native';
import { FocusablePressable } from './FocusablePressable';
import { scaledPixels } from '../hooks/useScale';

interface Props {
  visible: boolean;
  position: number; // seconds
  duration?: number; // seconds
  onResume: () => void;
  onStartOver: () => void;
  onDismiss?: () => void; // called on back button press
}

function formatTime(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.floor(seconds % 60);
  if (h > 0) {
    return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  }
  return `${m}:${String(s).padStart(2, '0')}`;
}

export default function ResumeDialog({ visible, position, duration, onResume, onStartOver, onDismiss }: Props) {
  const progressPercent =
    duration && duration > 0 ? Math.round((position / duration) * 100) : null;

  return (
    <Modal
      visible={visible}
      transparent
      animationType="fade"
      statusBarTranslucent
      onRequestClose={onDismiss ?? onStartOver}
    >
      <View style={styles.overlay}>
        <View style={styles.dialog}>
          <Text style={styles.title}>Resume Playback?</Text>
          <Text style={styles.subtitle}>
            {progressPercent !== null
              ? `You were ${progressPercent}% through (${formatTime(position)})`
              : `You were at ${formatTime(position)}`}
          </Text>

          <View style={styles.buttons}>
            <FocusablePressable
              preferredFocus
              onSelect={onResume}
              style={({ isFocused }) => [
                styles.button,
                styles.resumeButton,
                isFocused && styles.resumeButtonFocused,
              ]}
            >
              {() => <Text style={styles.resumeText}>Resume from {formatTime(position)}</Text>}
            </FocusablePressable>

            <FocusablePressable
              onSelect={onStartOver}
              style={({ isFocused }) => [
                styles.button,
                styles.startOverButton,
                isFocused && styles.startOverButtonFocused,
              ]}
            >
              {() => <Text style={styles.startOverText}>Start from Beginning</Text>}
            </FocusablePressable>
          </View>
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.75)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  dialog: {
    backgroundColor: '#1a1a2e',
    borderRadius: scaledPixels(12),
    padding: scaledPixels(32),
    width: scaledPixels(480),
    maxWidth: '80%',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
  },
  title: {
    color: '#fff',
    fontSize: scaledPixels(22),
    fontWeight: '700',
    marginBottom: scaledPixels(8),
  },
  subtitle: {
    color: 'rgba(255,255,255,0.7)',
    fontSize: scaledPixels(16),
    marginBottom: scaledPixels(28),
    textAlign: 'center',
  },
  buttons: {
    flexDirection: 'column',
    gap: scaledPixels(12),
    width: '100%',
  },
  button: {
    paddingVertical: scaledPixels(14),
    paddingHorizontal: scaledPixels(24),
    borderRadius: scaledPixels(8),
    alignItems: 'center',
    borderWidth: 2,
    borderColor: 'transparent',
  },
  resumeButton: {
    backgroundColor: '#6366f1',
  },
  resumeButtonFocused: {
    borderColor: '#fff',
    transform: [{ scale: 1.04 }],
  },
  startOverButton: {
    backgroundColor: 'transparent',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.3)',
  },
  startOverButtonFocused: {
    borderColor: '#fff',
    backgroundColor: 'rgba(255,255,255,0.1)',
    transform: [{ scale: 1.04 }],
  },
  resumeText: {
    color: '#fff',
    fontSize: scaledPixels(16),
    fontWeight: '600',
  },
  startOverText: {
    color: 'rgba(255,255,255,0.8)',
    fontSize: scaledPixels(16),
  },
});
