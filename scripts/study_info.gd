class_name StudyInfo
extends RefCounted

# Study information and consent text (Andrei, 4.11). PLACEHOLDER: replace these
# strings with the approved wording when the detailed guidelines arrive. Bump
# TEXT_VERSION whenever the wording changes; it is saved with every consent
# decision so the research data shows which text a participant agreed to.
# Square brackets mark details the team still has to fill in.

const TEXT_VERSION := "placeholder-2026-11-09"
const IS_PLACEHOLDER := true

const TITLE := "Before you play: research study"
const INTRO := "Beacon Bay is part of a university research project on teamwork and workload in emergency dispatch. Taking part is voluntary. You can play the whole game either way."

## Shown as headed paragraphs on the consent screen, in this order.
const SECTIONS := [
	["WHAT IS RECORDED", "If you agree: your mouse movements and clicks, the actions you take in the game, game events, short questionnaire answers and, only if you turn on voice chat and allow team recording, your own in-game voice. The name you type in the lobby labels your files, so you may use a nickname. No email addresses or other contact details are recorded."],
	["WHERE IT IS STORED AND ANALYSED", "Recordings are saved only on your own computer (not on the internet game server). After playing you send your session folder to the research team. The research team at [university / research group] analyses them on [university-managed storage] for [the course CT70A9500 and related research]. Data is kept until [date or retention period] and then deleted."],
	["HOW RESULTS ARE PUBLISHED", "Results are published only anonymously, for example in a course report or a scientific article. You cannot be identified from published results. Voice recordings are not published; [only derived measures such as speaking time are reported]."],
	["YOUR RIGHTS", "You can stop at any time. After playing you can withdraw: use WITHDRAW MY DATA on the main menu or in Settings > Research, and your recordings from the session are deleted from this computer. If you have already sent them, contact [researcher name, email]. Questions: [researcher name, email]."],
]

const AGREE := "I AGREE · RECORD MY PLAY"
const DECLINE := "PLAY WITHOUT DATA COLLECTION"
const PLACEHOLDER_NOTE := "Placeholder text: to be replaced with the approved study information."

const WITHDRAW_TITLE := "Withdraw from the study?"
const WITHDRAW_TEXT := "This deletes the study files of this play session from this computer: your mouse and game input, your questionnaire answers and your voice. Recording stops for you; you can keep playing."
const WITHDRAW_LATER := "If you already sent the files, or to withdraw an earlier session, contact [researcher name, email]."
