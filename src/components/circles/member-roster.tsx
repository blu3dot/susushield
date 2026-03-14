import { PixelAvatar, PixelBadge, PixelCard } from '@/components/ui'

interface Member {
  user_id: string
  rotation_position: number
  is_organizer: boolean
  profile: {
    display_name: string | null
    avatar_seed: string | null
  }
}

interface MemberRosterProps {
  members: Member[]
  currentUserId: string
}

export function MemberRoster({ members, currentUserId }: MemberRosterProps) {
  const sorted = [...members].sort((a, b) => a.rotation_position - b.rotation_position)

  return (
    <PixelCard>
      <div className="flex flex-col gap-3">
        <h2 className="font-[family-name:var(--font-display)] text-[10px] text-text-secondary uppercase">
          Members ({members.length})
        </h2>
        <div className="flex flex-col gap-2">
          {sorted.map((member) => (
            <div
              key={member.user_id}
              className="flex items-center gap-3 p-2 bg-bg-void border border-border-dim"
            >
              <PixelAvatar
                seed={member.profile?.avatar_seed ?? member.user_id}
                size="sm"
              />
              <div className="flex-1 min-w-0">
                <span className="font-[family-name:var(--font-body)] text-sm text-text-primary truncate block">
                  {member.profile?.display_name ?? 'Anonymous'}
                  {member.user_id === currentUserId && (
                    <span className="text-accent ml-1">(you)</span>
                  )}
                </span>
              </div>
              <span className="font-[family-name:var(--font-mono)] text-xs text-text-muted">
                #{member.rotation_position}
              </span>
              {member.is_organizer && (
                <PixelBadge variant="accent">ORG</PixelBadge>
              )}
            </div>
          ))}
        </div>
      </div>
    </PixelCard>
  )
}
