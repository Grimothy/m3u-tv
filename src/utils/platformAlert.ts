export function showAlert(title: string, message?: string): void {
  window.alert(message ? `${title}\n\n${message}` : title);
}

export function showConfirm(title: string, message: string, onConfirm: () => void): void {
  if (window.confirm(`${title}\n\n${message}`)) {
    onConfirm();
  }
}
