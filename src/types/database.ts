// Database types matching Supabase schema

export type CircleStatus = 'forming' | 'active' | 'completed' | 'paused'
export type MemberStatus = 'active' | 'removed' | 'left'
export type RoundStatus = 'pending' | 'active' | 'completed'
export type ContributionStatus = 'pending' | 'sent' | 'confirmed' | 'late' | 'missed'
export type PaymentMethod = 'venmo' | 'zelle' | 'cashapp' | 'cash' | 'other'
export type EmergencyPrivacy = 'public' | 'anonymous'
export type EmergencyStatus = 'pending' | 'approved' | 'rejected' | 'expired'
export type EmergencyVote = 'approve' | 'reject' | 'abstain'
export type Frequency = 'weekly' | 'bi-weekly' | 'monthly'

export interface Profile {
  id: string
  email: string
  display_name: string | null
  avatar_seed: string | null
  reputation_score: number
  created_at: string
  updated_at: string
}

export interface PaymentHandle {
  id: string
  user_id: string
  method: PaymentMethod
  handle: string
  created_at: string
}

export interface Circle {
  id: string
  name: string
  contribution_amount: number
  frequency: Frequency
  max_members: number
  invite_code: string
  invite_expires_at: string | null
  status: CircleStatus
  created_by: string
  created_at: string
  updated_at: string
}

export interface Member {
  id: string
  circle_id: string
  user_id: string
  rotation_position: number
  is_organizer: boolean
  status: MemberStatus
  joined_at: string
}

export interface Round {
  id: string
  circle_id: string
  round_number: number
  recipient_id: string
  status: RoundStatus
  due_date: string
  started_at: string | null
  completed_at: string | null
  created_at: string
}

export interface Contribution {
  id: string
  round_id: string
  circle_id: string
  member_id: string
  user_id: string
  status: ContributionStatus
  payment_method: PaymentMethod | null
  sent_at: string | null
  confirmed_at: string | null
  confirmed_by: string | null
  created_at: string
}

export interface ContributionAudit {
  id: string
  contribution_id: string
  old_status: ContributionStatus | null
  new_status: ContributionStatus
  changed_by: string
  changed_at: string
  reason: string | null
}

export interface EmergencyRequest {
  id: string
  circle_id: string
  requestor_id: string
  amount: number
  reason: string | null
  privacy: EmergencyPrivacy
  status: EmergencyStatus
  voting_deadline: string
  created_at: string
}

export interface EmergencyVoteRecord {
  id: string
  request_id: string
  voter_id: string
  vote: EmergencyVote
  voted_at: string
}

// Joined types for UI
export interface MemberWithProfile extends Member {
  profile: Profile
}

export interface RoundWithContributions extends Round {
  contributions: ContributionWithMember[]
}

export interface ContributionWithMember extends Contribution {
  member: MemberWithProfile
}

export interface CircleWithMembers extends Circle {
  members: MemberWithProfile[]
  current_round: Round | null
}
