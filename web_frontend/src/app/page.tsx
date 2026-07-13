'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Modal } from '@/components/ui/modal';
import { Skeleton } from '@/components/ui/skeleton';
import { useAppStore } from '@/store/useAppStore';

export default function Home() {
  const [sequence, setSequence] = useState('');
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [isAnalyzing, setIsAnalyzing] = useState(false);
  const { encryptionMode, setEncryptionMode } = useAppStore();

  const handleAnalyze = () => {
    setIsAnalyzing(true);
    // Simulate API Call delay
    setTimeout(() => {
      setIsAnalyzing(false);
      setIsModalOpen(true);
    }, 2000);
  };

  return (
    <main className="flex-1 p-6 max-w-4xl mx-auto w-full">
      {/* Header Section */}
      <header className="flex justify-between items-center mb-10 pb-4 border-b border-dark-tech-800">
        <div>
          <h1 className="text-3xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-cyan-neon to-blue-500">
            Golden P. 
          </h1>
          <p className="text-gray-500 text-sm mt-1">Advanced Bot Predictor & Analyzer</p>
        </div>
        
        {/* State Management Toggle Example */}
        <div className="flex items-center gap-3 bg-dark-tech-800 p-1.5 rounded-lg border border-dark-tech-700">
          <button 
            onClick={() => setEncryptionMode('standard')}
            className={`px-3 py-1.5 text-xs font-medium rounded-md transition-colors ${encryptionMode === 'standard' ? 'bg-gray-700 text-white' : 'text-gray-400 hover:text-gray-200'}`}
          >
            Standard
          </button>
          <button 
            onClick={() => setEncryptionMode('maximum')}
            className={`px-3 py-1.5 text-xs font-medium rounded-md transition-colors ${encryptionMode === 'maximum' ? 'bg-cyan-neon/20 text-cyan-neon border border-cyan-neon/50 shadow-[0_0_10px_rgba(0,229,255,0.2)]' : 'text-gray-400 hover:text-gray-200'}`}
          >
            Max Shield
          </button>
        </div>
      </header>

      {/* Main Content Area */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        
        {/* Analysis Panel */}
        <section className="bg-dark-tech-900 border border-dark-tech-800 rounded-xl p-6 shadow-2xl relative overflow-hidden">
          <div className="absolute top-0 right-0 w-32 h-32 bg-cyan-neon/5 blur-[80px] rounded-full pointer-events-none"></div>
          
          <h2 className="text-xl font-semibold mb-6 flex items-center gap-2 text-white">
            <span className="w-2 h-2 rounded-full bg-cyan-neon animate-pulse"></span>
            Sequence Analyzer
          </h2>
          
          <div className="space-y-6">
            <div>
              <label className="block text-xs font-medium text-gray-400 mb-2 uppercase tracking-wider">
                Target Sequence (A/B/C)
              </label>
              <Input 
                value={sequence}
                onChange={(e) => setSequence(e.target.value.toUpperCase())}
                placeholder="Enter sequence pattern..." 
                maxLength={20}
              />
            </div>

            <Button 
              className="w-full h-12 text-lg uppercase tracking-widest font-bold"
              onClick={handleAnalyze}
              isLoading={isAnalyzing}
              disabled={sequence.length < 3}
            >
              Execute Prediction
            </Button>
          </div>
        </section>

        {/* Stats / Skeleton Panel */}
        <section className="bg-dark-tech-800/30 border border-dark-tech-800 rounded-xl p-6 shadow-lg">
          <h2 className="text-lg font-medium mb-4 text-gray-300">Live Telemetry</h2>
          
          {/* Skeleton Loaders matching UI expectations */}
          <div className="space-y-4">
            <div className="flex justify-between items-center pb-2 border-b border-dark-tech-800">
              <span className="text-gray-500 text-sm">Latency</span>
              {isAnalyzing ? <Skeleton className="h-4 w-12" /> : <span className="text-green-400 text-sm font-mono">12ms</span>}
            </div>
            <div className="flex justify-between items-center pb-2 border-b border-dark-tech-800">
              <span className="text-gray-500 text-sm">Confidence Rating</span>
              {isAnalyzing ? <Skeleton className="h-4 w-16" /> : <span className="text-cyan-neon text-sm font-mono">98.4%</span>}
            </div>
            <div className="flex justify-between items-center">
              <span className="text-gray-500 text-sm">Active Engine</span>
              {isAnalyzing ? <Skeleton className="h-4 w-24" /> : <span className="text-white text-sm font-mono">Shadow Hunter V18</span>}
            </div>
          </div>
        </section>

      </div>

      {/* Confirmation/Result Modal */}
      <Modal 
        isOpen={isModalOpen} 
        onClose={() => setIsModalOpen(false)} 
        title="Prediction Completed"
      >
        <div className="text-center">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-cyan-neon/10 mb-4 border border-cyan-neon/30">
            <svg className="w-8 h-8 text-cyan-neon" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
            </svg>
          </div>
          <h4 className="text-xl font-bold text-white mb-2">High Probability Match</h4>
          <p className="text-gray-400 mb-6">
            The AI engine predicts that the next optimal move based on sequence <strong className="text-cyan-neon tracking-widest">{sequence}</strong> is <strong className="text-white text-lg">A</strong>.
          </p>
          <Button className="w-full" onClick={() => setIsModalOpen(false)}>Acknowledge & Close</Button>
        </div>
      </Modal>
    </main>
  );
}
