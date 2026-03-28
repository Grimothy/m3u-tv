const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  platform: process.platform,
  isElectron: true,
  openExternal: (url, startPosition) => ipcRenderer.invoke('open-external', url, startPosition || 0),
  onExternalPlayerClosed: (callback) => {
    ipcRenderer.on('external-player-closed', () => callback());
    return () => ipcRenderer.removeAllListeners('external-player-closed');
  },
});
