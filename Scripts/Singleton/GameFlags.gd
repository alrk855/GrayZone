# Central flag catalog + legacy aliases 
extends Node
class_name GameFlags

# ===== Canonical names =====
# Secretary / MVR / Printing
const SECRETARY_MET              := "secretary_met"
const HAVE_BIRTH_CERTIFICATE     := "have_birth_certificate"
const NOTARIZED_BIRTH            := "notarized_birth"

const PRINTED_CV                 := "printed_cv"
const PRINTED_MOTIVATION         := "printed_motivation"
const PRINTED_PROJECT            := "printed_project"

# MVR / Birth Certificate flow
const MVR_BCERT_STARTED          := "mvr_bcert_started"       # chose a path (any)
const MVR_BCERT_STANDARD         := "mvr_bcert_standard"      # chose standard flow
const MVR_BCERT_EXPEDITED        := "mvr_bcert_expedited"     # chose expedited flow
const MVR_BCERT_BRIBERY          := "mvr_bcert_bribery"       # paid the bribe (same-day)

# Project / Professor / Janitor
const BOUGHT_PROJECT             := "bought_project"
const PROJECT_WRITTEN            := "project_written"
const PROJECT_ACCEPTED           := "project_accepted"
const PROJECT_SUBMITTED          := "project_submitted"
const PROJECT_PLAGIARIZED        := "project_plagiarized"

const PROJECT_SECOND_CHANCE      := "project_second_chance"      # gate re-writing in Home
const PROJECT_PROMISE_TOMORROW   := "project_promise_tomorrow"   # promise made
const PROJECT_PROMISE_DAY        := "project_promise_day"        # int day value

# City / Misc
const SPENT_MONEY_ONCE           := "spent_money_once"
const YCO_INTERACTION            := "yco_interaction_done"        # Youth Center/Office unlocked

# Marko / First Event
const MARKO_FIRST_EVENT_DONE     := "marko_first_event_done"
const TIPPED                     := "marko_tip"                   # Marko’s janitor tip

# Task Manager misc
const REQ_SUBTASKS               := "req_subtasks_added"

# ===== Classroom / Teacher flow =====
const TEACHER_D2_EVENT_DONE      := "teacher_d2_event_done"       # Day-2 noon talk completed (or catch-up unlock)
const TEACHER_REVIEW_UNLOCKED    := "teacher_review_unlocked"     # Can ask teacher to review CV/M-letter
const TEACHER_REVIEW_DONE        := "teacher_review_done"         # Review completed (menu item should hide unless second-chance active)

# Attendance
const DISCIPLINE_WARNING         := "discipline_warning"          
const DISCIPLINE_FAILED          := "discipline_failed"           
const ABSENT_COUNT               := "absent_count"                
const LATE_COUNT                 := "late_count"                  
const HOMEROOM_CATCHUP_SHOWN     := "homeroom_catchup_shown"      

# Transcripts
const TRANSCRIPTS_READY          := "transcripts_ready"
const TRANSCRIPTS_GIVEN          := "transcripts_given"

# Janitor answers (slot-based; independent of actual subject names)
const BOUGHT_ANSWERS_S1          := "bought_answers_s1"
const BOUGHT_ANSWERS_S2          := "bought_answers_s2"
const JANITOR_OFFER_DECLINED_D3  := "janitor_offer_declined_d3"

# Motivation letter review state
const MLETTER_AI                 := "motivation_ai_generated"     # set by M-letter scene if GPT path used
const MLETTER_REWRITE_REQUIRED   := "motivation_rewrite_required" # need rewrite; also implies reprint

# Scholarship requirement: Language certificate (arrived via mailbox)
const HAVE_LANGUAGE_CERTIFICATE  := "have_language_certificate"

# ===== Manual override (dev/testing) =====
# When TRUE → teacher ALWAYS catches AI letter during review (no RNG). When FALSE → normal behavior (50/50 only if AI).
const DOC_FORCE_CATCH            := "doc_force_catch"
# When TRUE → professor ALWAYS catches project plagiarism (no RNG). When FALSE → normal behavior.
const PROJECT_FORCE_PLAG_CAUGHT  := "project_force_plag_caught"

# ===== Defaults (types are respected) =====
const DEFAULTS := {
	SECRETARY_MET: false,
	HAVE_BIRTH_CERTIFICATE: false,
	NOTARIZED_BIRTH: false,

	PRINTED_CV: false,
	PRINTED_MOTIVATION: false,
	PRINTED_PROJECT: false,

	# MVR (note: ready-day handled elsewhere)
	MVR_BCERT_STARTED: false,
	MVR_BCERT_STANDARD: false,
	MVR_BCERT_EXPEDITED: false,
	MVR_BCERT_BRIBERY: false,

	BOUGHT_PROJECT: false,
	PROJECT_WRITTEN: false,
	PROJECT_ACCEPTED: false,
	PROJECT_SUBMITTED: false,
	PROJECT_PLAGIARIZED: false,

	PROJECT_SECOND_CHANCE: false,
	PROJECT_PROMISE_TOMORROW: false,
	PROJECT_PROMISE_DAY: 0,

	SPENT_MONEY_ONCE: false,
	YCO_INTERACTION: false,

	MARKO_FIRST_EVENT_DONE: false,
	TIPPED: false,
	REQ_SUBTASKS: false,

	# Classroom / teacher
	TEACHER_D2_EVENT_DONE: false,
	TEACHER_REVIEW_UNLOCKED: false,
	TEACHER_REVIEW_DONE: false,

	# Attendance
	DISCIPLINE_WARNING: false,
	DISCIPLINE_FAILED: false,
	ABSENT_COUNT: 0,
	LATE_COUNT: 0,
	HOMEROOM_CATCHUP_SHOWN: false,

	# Transcripts
	TRANSCRIPTS_READY: false,
	TRANSCRIPTS_GIVEN: false,

	# Janitor answers
	BOUGHT_ANSWERS_S1: false,
	BOUGHT_ANSWERS_S2: false,
	JANITOR_OFFER_DECLINED_D3: false,

	# Motivation letter review state
	MLETTER_AI: false,
	MLETTER_REWRITE_REQUIRED: false,

	# Scholarship requirement
	HAVE_LANGUAGE_CERTIFICATE: false,

	# Manual overrides
	DOC_FORCE_CATCH: false,
	PROJECT_FORCE_PLAG_CAUGHT: false,
}

# ===== Legacy → Canonical map =====
const ALIASES := {
	# project promise variants seen in JSON/scripts
	"project_tomorrow_promise": PROJECT_PROMISE_TOMORROW,
	"bring_tomorrow_promised": PROJECT_PROMISE_TOMORROW,
	"project_promise": PROJECT_PROMISE_TOMORROW,

	# due-date hints (keep as-is, no behavior change)
	"project_due_friday_noon": "project_due_friday_noon",
	"project_due_day4_eod": "project_due_day4_eod",

	# convenience aliases for newer flags
	"yco_interaction": YCO_INTERACTION,
	"marko_tipped": TIPPED,
	"tipped_by_marko": TIPPED,

	"teacher_event_done": TEACHER_D2_EVENT_DONE,
	"teacher_review": TEACHER_REVIEW_UNLOCKED,
	"teacher_review_done": TEACHER_REVIEW_DONE,

	"discipline_warn": DISCIPLINE_WARNING,
	"discipline_warning": DISCIPLINE_WARNING,
	"discipline_fail": DISCIPLINE_FAILED,
	"bad_record": DISCIPLINE_FAILED,

	"absences": ABSENT_COUNT,
	"lateness": LATE_COUNT,

	"bought_answers_subject1": BOUGHT_ANSWERS_S1,
	"bought_answers_subject2": BOUGHT_ANSWERS_S2,

	"transcripts_ready": TRANSCRIPTS_READY,
	"transcripts_received": TRANSCRIPTS_GIVEN,

	"motivation_ai": MLETTER_AI,
	"motivation_ai_generated": MLETTER_AI,
	"motivation_rewrite_required": MLETTER_REWRITE_REQUIRED,

	# Manual overrides legacy keys
	"force_plag_caught": PROJECT_FORCE_PLAG_CAUGHT,
	"force_doc_catch": DOC_FORCE_CATCH,
	"doc_force_catch": DOC_FORCE_CATCH,
}

static func canon(name: String) -> String:
	if name == "":
		return ""
	if ALIASES.has(name):
		return String(ALIASES[name])
	return name
