'use client'

import { useState } from 'react'
import { PixelButton, PixelCard } from '@/components/ui'

interface InviteShareProps {
  inviteCode: string
  circleId: string
}

export function InviteShare({ inviteCode }: InviteShareProps) {
  const [copied, setCopied] = useState(false)

  const inviteUrl = typeof window !== 'undefined'
    ? `${window.location.origin}/join/${inviteCode}`
    : `/join/${inviteCode}`

  async function handleShare() {
    if (navigator.share) {
      try {
        await navigator.share({
          title: 'Join my Susu Circle',
          text: 'Join my rotating savings circle!',
          url: inviteUrl,
        })
      } catch {
        // User cancelled share
      }
    } else {
      await handleCopy()
    }
  }

  async function handleCopy() {
    await navigator.clipboard.writeText(inviteUrl)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <PixelCard variant="accent">
      <div className="flex flex-col gap-3">
        <h2 className="font-[family-name:var(--font-display)] text-[10px] text-accent uppercase">
          Invite Members
        </h2>
        <div className="flex gap-2 items-center">
          <code className="flex-1 px-3 py-2 bg-bg-void border-2 border-border-dim font-[family-name:var(--font-mono)] text-sm text-text-primary truncate">
            {inviteCode}
          </code>
          <PixelButton size="sm" onClick={handleCopy} variant="secondary">
            {copied ? 'COPIED!' : 'COPY'}
          </PixelButton>
        </div>
        <PixelButton onClick={handleShare} className="w-full">
          SHARE INVITE
        </PixelButton>
      </div>
    </PixelCard>
  )
}
