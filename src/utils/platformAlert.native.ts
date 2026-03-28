import { Alert } from 'react-native';

export function showAlert(title: string, message?: string): void {
  Alert.alert(title, message);
}

export function showConfirm(title: string, message: string, onConfirm: () => void): void {
  Alert.alert(title, message, [
    { text: 'Cancel', style: 'cancel' },
    { text: 'Confirm', style: 'destructive', onPress: onConfirm },
  ]);
}
