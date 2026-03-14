import { PixelBadge } from '@/components/ui'

interface Round {
  id: string
  round_number: number
  recipient_id: string
  status: string
}

interface Member {
  user_id: string
  rotation_position: number
  profile: {
    display_name: string | null
  }
}

interface RotationTimelineProps {
  rounds: Round[]
  members: Member[]
  currentUserId: string
}

export function RotationTimeline({
  rounds,
  members,
  currentUserId,
}: RotationTimelineProps) {
  const currentMember = members.find((m) => m.user_id === currentUserId)
  const currentRound = rounds.find((r) => r.status === 'active')
  const turnsUntilYours = currentMember && currentRound
    ? currentMember.rotation_position - currentRound.round_number
    : null

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between">
        <h2 className="font-[family-name:var(--font-display)] text-[10px] text-text-secondary uppercase">
          Rotation
        </h2>
        {turnsUntilYours !== null && turnsUntilYours > 0 && (
          <span className="font-[family-name:var(--font-mono)] text-xs text-accent">
            Your turn in {turnsUntilYours} round{turnsUntilYours !== 1 ? 's' : ''}
          </span>
        )}
        {turnsUntilYours === 0 && (
          <PixelBadge variant="warning">YOUR TURN!</PixelBadge>
        )}
      </div>

      {/* Horizontal timeline */}
      <div className="flex gap-1 overflow-x-auto pb-2">
        {members
          .sort((a, b) => a.rotation_position - b.rotation_position)
          .map((member) => {
            const round = rounds.find(
              (r) => r.round_number === member.rotation_position,
            )
            const status = round?.status ?? 'future'
            const isYou = member.user_id === currentUserId

            return (
              <div
                key={member.user_id}
                className={`
                  flex flex-col items-center gap-1 min-w-[60px] p-2
                  border-2
                  ${status === 'completed' ? 'border-success/30 bg-success/5' : ''}
                  ${status === 'active' ? 'border-accent bg-accent/10' : ''}
                  ${status === 'pending' || status === 'future' ? 'border-border-dim bg-bg-void' : ''}
                `}
              >
                <span className="font-[family-name:var(--font-display)] text-[8px] text-text-muted">
                  R{member.rotation_position}
                </span>
                <span
                  className={`font-[family-name:var(--font-body)] text-xs text-center truncate w-full ${
                    isYou ? 'text-accent' : 'text-text-secondary'
                  }`}
                >
                  {isYou ? 'You' : (member.profile?.display_name?.split(' ')[0] ?? '?')}
                </span>
                <div
                  className={`w-2 h-2 ${
                    status === 'completed' ? 'bg-success' : ''
                  } ${status === 'active' ? 'bg-accent animate-pixel-pulse' : ''} ${
                    status === 'pending' || status === 'future' ? 'bg-border-dim' : ''
                  }`}
                />
              </div>
            )
          })}
      </div>
    </div>
  )
}
