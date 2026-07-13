import React from 'react';

interface SkeletonProps {
  className?: string;
}

export function Skeleton({ className = '' }: SkeletonProps) {
  return (
    <div
      className={`animate-pulse rounded-md bg-dark-tech-800/50 ${className}`}
      aria-busy="true"
      aria-hidden="true"
    />
  );
}
