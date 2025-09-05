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

# Marko first event
const MARKO_FIRST_EVENT_DONE     := "marko_first_event_done"
const TIPPED                     := "marko_tip"

# Legacy compatibility (still used in some JSONs)
const HAVE_OLD_PROJECT           := "have_old_project"
const PRINTED_TRANSCRIPT         := "printed_transcript"
const INTEGRITY_PENALTY_PENDING  := "integrity_penalty_pending"

# ===== Defaults (types are respected) =====
const DEFAULTS := {
	SECRETARY_MET: false,
	HAVE_BIRTH_CERTIFICATE: false,
	NOTARIZED_BIRTH: false,

	PRINTED_CV: false,
	PRINTED_MOTIVATION: false,
	PRINTED_PROJECT: false,

	BOUGHT_PROJECT: false,
	PROJECT_WRITTEN: false,
	PROJECT_ACCEPTED: false,
	PROJECT_SUBMITTED: false,
	PROJECT_PLAGIARIZED: false,

	PROJECT_SECOND_CHANCE: false,
	PROJECT_PROMISE_TOMORROW: false,
	PROJECT_PROMISE_DAY: 0,

	SPENT_MONEY_ONCE: false,

	MARKO_FIRST_EVENT_DONE: false,
	TIPPED: false,
	HAVE_OLD_PROJECT: false,
	PRINTED_TRANSCRIPT: false,
	INTEGRITY_PENALTY_PENDING: false,
}

# ===== Legacy → Canonical map =====
const ALIASES := {
	# promise variants seen in JSON/scripts
	"project_tomorrow_promise": PROJECT_PROMISE_TOMORROW,
	"bring_tomorrow_promised": PROJECT_PROMISE_TOMORROW,
	"project_promise": PROJECT_PROMISE_TOMORROW,

	# due-date hints (keep as-is, no behavior change)
	"project_due_friday_noon": "project_due_friday_noon",
	"project_due_day4_eod": "project_due_day4_eod",

	# old → new links
	HAVE_OLD_PROJECT: BOUGHT_PROJECT,  # treat old as bought
}

static func canon(name: String) -> String:
	if name == "":
		return ""
	if ALIASES.has(name):
		return String(ALIASES[name])
	return name
