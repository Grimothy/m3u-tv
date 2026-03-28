export async function getSecureItem(key: string): Promise<string | null> {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

export async function setSecureItem(key: string, value: string): Promise<void> {
  try {
    localStorage.setItem(key, value);
  } catch {
    console.warn('Failed to save to localStorage');
  }
}

export async function deleteSecureItem(key: string): Promise<void> {
  try {
    localStorage.removeItem(key);
  } catch {
    console.warn('Failed to delete from localStorage');
  }
}
