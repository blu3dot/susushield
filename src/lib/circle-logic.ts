import type { ContributionStatus, RoundStatus } from '@/types/database'

/**
 * Valid contribution status transitions.
 * Every transition must be explicitly defined here.
 */
export const VALID_TRANSITIONS: Record<ContributionStatus, ContributionStatus[]> = {
  pending: ['sent', 'late', 'missed'],
  sent: ['confirmed', 'late', 'missed'],
  confirmed: [], // terminal
  late: ['sent', 'missed'], // can still pay after late
  missed: [], // terminal
}

/**
 * Check if a status transition is valid.
 */
export function isValidTransition(
  from: ContributionStatus,
  to: ContributionStatus,
): boolean {
  return VALID_TRANSITIONS[from]?.includes(to) ?? false
}

/**
 * Check if all contributions in a round are confirmed.
 */
export function isRoundComplete(
  statuses: ContributionStatus[],
): boolean {
  return statuses.length > 0 && statuses.every((s) => s === 'confirmed')
}

/**
 * Get the recipient for a given round number based on rotation position.
 * Members are sorted by rotation_position; round N's recipient is position N.
 */
export function getRecipientForRound(
  members: { user_id: string; rotation_position: number }[],
  roundNumber: number,
): string | null {
  const sorted = [...members].sort((a, b) => a.rotation_position - b.rotation_position)
  const recipient = sorted.find((m) => m.rotation_position === roundNumber)
  return recipient?.user_id ?? null
}

/**
 * Compute the total payout amount for a round.
 * Every member contributes the circle amount; the recipient gets the full pot.
 */
export function computePayoutAmount(
  contributionAmount: number,
  memberCount: number,
): number {
  return contributionAmount * memberCount
}

/**
 * Determine the next round number after the current one.
 */
export function getNextRoundNumber(
  currentRoundNumber: number,
  totalMembers: number,
): number | null {
  const next = currentRoundNumber + 1
  return next <= totalMembers ? next : null
}

/**
 * Generate a cryptographically random invite code.
 */
export function generateInviteCode(length = 8): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' // removed ambiguous: 0/O, 1/I/L
  const array = new Uint8Array(length)
  crypto.getRandomValues(array)
  return Array.from(array, (byte) => chars[byte % chars.length]).join('')
}

/**
 * Calculate due date for a round based on frequency and start date.
 */
export function calculateDueDate(
  startDate: Date,
  frequency: 'weekly' | 'bi-weekly' | 'monthly',
): Date {
  const due = new Date(startDate)
  switch (frequency) {
    case 'weekly':
      due.setDate(due.getDate() + 7)
      break
    case 'bi-weekly':
      due.setDate(due.getDate() + 14)
      break
    case 'monthly':
      due.setMonth(due.getMonth() + 1)
      break
  }
  return due
}

/**
 * Check if a contribution is past its grace period.
 * Default grace period: 3 days after due date for "late", 7 days for "missed".
 */
export function getContributionUrgency(
  dueDate: Date,
  now: Date = new Date(),
): 'on-time' | 'grace' | 'late' | 'missed' {
  const diff = now.getTime() - dueDate.getTime()
  const days = diff / (1000 * 60 * 60 * 24)

  if (days <= 0) return 'on-time'
  if (days <= 3) return 'grace'
  if (days <= 7) return 'late'
  return 'missed'
}
