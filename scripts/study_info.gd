class_name StudyInfo
extends RefCounted

# Study information and consent text (Andrei, 4.11). PLACEHOLDER: replace these
# strings with the approved wording when the detailed guidelines arrive. Bump
# TEXT_VERSION whenever the wording changes; it is saved with every consent
# decision so the research data shows which text a participant agreed to.
# Square brackets mark details the team still has to fill in.

const TEXT_VERSION := "placeholder-2026-11-04"
const IS_PLACEHOLDER := true

const TITLE := "Before you play: research study"
const INTRO := "Beacon Bay is part of a university research project on teamwork and workload in emergency dispatch. Taking part is voluntary. You can play the whole game either way."

## Shown as headed paragraphs on the consent screen, in this order.
const SECTIONS := [
	["WHAT IS RECORDED", "If you agree: your mouse movements and clicks, the actions you take in the game, game events, short questionnaire answers and, only if you turn on voice chat and allow team recording, your in-game voice. No names, email addresses or other contact details are recorded."],
	["WHERE IT IS STORED AND ANALYSED", "Recordings are saved on the study computer of the session leader (not on the internet game server). The research team at [university / research group] analyses them on [university-managed storage] for [the course CT70A9500 and related research]. Data is kept until [date or retention period] and then deleted."],
	["HOW RESULTS ARE PUBLISHED", "Results are published only anonymously, for example in a course report or a scientific article. You cannot be identified from published results. Voice recordings are not published; [only derived measures such as speaking time are reported]."],
	["YOUR RIGHTS", "You can stop at any time. After playing you can withdraw: use WITHDRAW MY DATA on the main menu or in Settings > Research, and your recordings from the session are deleted. Questions: [researcher name, email]."],
]

const AGREE := "I AGREE · RECORD MY PLAY"
const DECLINE := "PLAY WITHOUT DATA COLLECTION"
const PLACEHOLDER_NOTE := "Placeholder text: to be replaced with the approved study information."

const WITHDRAW_TITLE := "Withdraw from the study?"
const WITHDRAW_TEXT := "This deletes what was recorded about you in this play session: your mouse and game input, your questionnaire answers and your voice track. Recording stops for you; you can keep playing."
const WITHDRAW_COOP := "In co-op the request goes to the session leader's computer, which deletes your data there. If the leader has already left, contact [researcher name, email]."
const WITHDRAW_OFFLINE := "You played as a teammate, so your recordings are on the session leader's computer, and you have left that room. To withdraw, give this code to [researcher name, email]; they will delete your data."
const WITHDRAW_LATER := "To withdraw data from an earlier session, contact [researcher name, email]."
