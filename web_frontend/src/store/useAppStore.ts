import { create } from 'zustand';

interface AppState {
  isSidebarOpen: boolean;
  toggleSidebar: () => void;
  encryptionMode: 'standard' | 'maximum';
  setEncryptionMode: (mode: 'standard' | 'maximum') => void;
}

export const useAppStore = create<AppState>((set) => ({
  isSidebarOpen: false,
  toggleSidebar: () => set((state) => ({ isSidebarOpen: !state.isSidebarOpen })),
  encryptionMode: 'maximum',
  setEncryptionMode: (mode) => set({ encryptionMode: mode }),
}));
