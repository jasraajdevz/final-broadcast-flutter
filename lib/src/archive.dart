// FINAL BROADCAST — THE ARCHIVE.
//
// Two problems, one answer.
//
// "add alot of lore" — the station had a premise and nine pages of one man's
// log, and then nothing. A haunted building with no paperwork is a set.
//
// "it aint still addictive" — after sign-off there was nothing pulling you
// back. The night card gave tomorrow a NAME, which is a start, but a name is
// not a reason. Nothing in the game was ever unfinished in a way you wanted to
// finish.
//
// So: one document recovered every single night, forever, in a fixed order,
// with the count of what is still missing on the front desk. "37 OF 54
// RECOVERED" is the entire hook. You do not come back for the numbers, you
// come back because there is a page 38 and you have read 37.
//
// The order is authored, not random. It is a story: a station that has been
// holding something down since 1963, the men who held it, and the slow
// arrival of the fact that the roster has your name on it and always has.

import 'state.dart';
import 'wallclock.dart';

enum DocKind {
  /// R. HALLORAN's operator log. The spine of the whole thing.
  log,

  /// Internal station paperwork. Bureaucracy is the scariest voice available:
  /// it describes atrocities in the register of a stock check.
  memo,

  /// Letters in from the public. They watched something they should not have.
  letter,

  /// Engineering. The men who built the lid and knew what it was for.
  engineering,

  /// Transcripts of what went out. Nobody scheduled these.
  transcript,
}

class StationDoc {
  const StationDoc({
    required this.kind,
    required this.head,
    required this.body,
    this.sign,
  });

  final DocKind kind;

  /// The dateline / letterhead.
  final String head;
  final String body;

  /// The line under it, if it is signed.
  final String? sign;

  String get kindLabel => switch (kind) {
        DocKind.log => 'OPERATOR LOG',
        DocKind.memo => 'STATION MEMO',
        DocKind.letter => 'VIEWER CORRESPONDENCE',
        DocKind.engineering => 'ENGINEERING',
        DocKind.transcript => 'TRANSCRIPT',
      };
}

/// One per night, in order, from night 2. Authored as a sequence — the early
/// ones are mundane, the late ones are not, and the turn happens slowly enough
/// that you are not sure exactly when it did.
const List<StationDoc> kArchive = <StationDoc>[
  StationDoc(
    kind: DocKind.log,
    head: 'FROM THE DESK DRAWER — LOG OF R. HALLORAN, NIGHT OPERATOR',
    body: 'Whoever is reading this: the rundown is a lie and the quotas are '
        'real. Keep the needle up. It does not care what you broadcast, only '
        'that you are broadcasting.',
  ),
  StationDoc(
    kind: DocKind.memo,
    head: 'KBLK-7 — TO ALL OVERNIGHT STAFF — 11 MARCH 1971',
    body: 'The transmitter is not to be taken off air for maintenance, '
        'weather, power supply, industrial action, or any other reason. '
        'Maintenance is to be carried out live. If this is not possible, it '
        'is to be carried out anyway.',
    sign: 'H. BRENNAN, STATION MANAGER',
  ),
  StationDoc(
    kind: DocKind.log,
    head: 'HALLORAN — NIGHT 214',
    body: 'Eight of them. There have only ever been eight. I have a key for '
        'each and I have never needed a ninth, which I used to find '
        'comforting.',
  ),
  StationDoc(
    kind: DocKind.engineering,
    head: 'MERIDIAN CATHODE LTD — INSTALLATION NOTE, MODEL 7',
    body: 'The set in booth two is not a monitor. It is the aerial. Anything '
        'that appears on it is already inside the building, and the picture '
        'is the last place you will see it before the room is.',
    sign: 'FITTED 1963. DO NOT REPLACE.',
  ),
  StationDoc(
    kind: DocKind.letter,
    head: 'LETTER — POSTMARKED 2 OCTOBER 1974',
    body: 'Dear Sir, my husband sat up with your station on Tuesday night as '
        'he cannot sleep. He says a man on the test card said his name and '
        'the name of our road. He will not go in that room now. We do not '
        'want an apology. We want to know how you knew.',
  ),
  StationDoc(
    kind: DocKind.log,
    head: 'HALLORAN — NIGHT 341',
    body: 'They have started arriving in the order I think of them in. I have '
        'stopped keeping the list in order.',
  ),
  StationDoc(
    kind: DocKind.memo,
    head: 'KBLK-7 — OPERATOR ROSTER, REVISED — 4 JANUARY 1976',
    body: 'The overnight shift is a one-man post and will remain a one-man '
        'post. Requests for a second operator have been declined on the '
        'grounds that a second operator has, historically, not survived the '
        'arrangement any better than the first.',
    sign: 'H. BRENNAN',
  ),
  StationDoc(
    kind: DocKind.log,
    head: 'HALLORAN — NIGHT 508',
    body: 'The window in the booth does not open and has never opened. '
        'Whatever is in the field is not getting in that way. I want to be '
        'clear that this is the only reassuring sentence in this book.',
  ),
  StationDoc(
    kind: DocKind.transcript,
    head: 'OFF-AIR RECORDING — 03:14, 19 JUNE 1977 — UNSCHEDULED',
    body: '[TONE, 1000Hz, 41 SECONDS]\n'
        '"...and that is the end of the programmes for tonight. We close down '
        'now. We close down now. We close down now. We close down now. We do '
        'not close down. Goodnight."',
  ),
  StationDoc(
    kind: DocKind.engineering,
    head: 'CARRIER NOTE — UNSIGNED, PENCIL, ON THE BACK OF A SCHEDULE',
    body: 'Asked Brennan what happens if it drops. He said it has never '
        'dropped. I said that is not what I asked. He said it has never '
        'dropped, and wrote it down, as if writing it down was the job.',
  ),
  StationDoc(
    kind: DocKind.log,
    head: 'HALLORAN — NIGHT 720',
    body: 'Slept four hours in the chair with the carrier up. Woke to find the '
        'log open at a page I had not written yet. The handwriting is mine.',
  ),
  StationDoc(
    kind: DocKind.letter,
    head: 'LETTER — POSTMARKED 30 NOVEMBER 1979',
    body: 'I am eleven. I am not supposed to be up. There was a lady on your '
        'channel standing very still in front of the colour bars and she was '
        'not on the colour bars, she was in front of them, and the bars went '
        'behind her properly like she was in the room where you make it. I '
        'waved. She waved back after a bit.',
  ),
  StationDoc(
    kind: DocKind.memo,
    head: 'KBLK-7 — NOTICE TO ENGINEERING — 8 AUGUST 1981',
    body: 'The pen recorder in booth two is to be inked at the start of every '
        'shift without exception. The trace is not a formality. If the trace '
        'stops, the operator is to assume the trace is correct and that he is '
        'the thing that has stopped.',
  ),
  StationDoc(
    kind: DocKind.log,
    head: 'HALLORAN — NIGHT 901',
    body: 'It is not trying to get out. I have had this backwards for two '
        'years. It is trying to get me to stop, which is a different thing, '
        'and it is much more patient about it.',
  ),
  StationDoc(
    kind: DocKind.engineering,
    head: 'MAST LOG — CLIMB REPORT, 12 FEBRUARY 1982',
    body: 'Went up to change the beacon. There are handholds worn into the '
        'ladder above the two hundred foot mark, on the inside face, where '
        'nobody climbing would put their hands. They are worn deep. Whatever '
        'made them has been going up and down that mast for a very long time '
        'and it does not use the rungs.',
  ),
  StationDoc(
    kind: DocKind.transcript,
    head: 'OFF-AIR RECORDING — 04:02, 3 MAY 1983 — UNSCHEDULED',
    body: '[NO VIDEO. AUDIO ONLY.]\n'
        '"Is he still there."\n'
        '"He is still there."\n'
        '"He has been there a long time."\n'
        '"He will not be there a long time."\n'
        '[TONE RESUMES]',
  ),
  StationDoc(
    kind: DocKind.memo,
    head: 'KBLK-7 — FROM THE OFFICE OF H. BRENNAN — 1 DECEMBER 1984',
    body: 'To the night operator. You will have noticed that nobody thanks '
        'you and that the day staff do not meet your eye. This is not '
        'unkindness. They have read the file and you have not, and they have '
        'decided that the difference is the only thing keeping you at that '
        'desk. I am inclined to agree with them.',
  ),
  StationDoc(
    kind: DocKind.log,
    head: 'HALLORAN — NIGHT 1,114',
    body: 'There is a second operator on the roster now. I have not met them. '
        'I have not been told their name. The roster is in my handwriting.',
  ),
  StationDoc(
    kind: DocKind.log,
    head: 'HALLORAN — FINAL ENTRY',
    body: 'If you are new: it is not the noise. It is the quiet after the '
        'noise, when you have got it right and you are sitting there being '
        'pleased with yourself. That is when it looks at you properly.',
  ),
  StationDoc(
    kind: DocKind.memo,
    head: 'STATION MEMO — UNSIGNED, UNDATED',
    body: 'R. HALLORAN did not sign off on the morning of the 1,115th night. '
        'The carrier was up. The chair was warm. The log was open to a blank '
        'page, and the page is the one you have been writing on.',
  ),
  StationDoc(
    kind: DocKind.engineering,
    head: 'FCC — NOTICE OF LICENCE REVOCATION — 14 JULY 1987',
    body: 'Authority to broadcast on 1,140 kHz is withdrawn effective '
        'immediately. All transmission is to cease. Confirmation of shutdown '
        'is required in writing within seven days.',
    sign: 'NO CONFIRMATION WAS EVER RECEIVED.',
  ),
  StationDoc(
    kind: DocKind.memo,
    head: 'KBLK-7 — INTERNAL, 15 JULY 1987',
    body: 'We are not going to comply and we are not going to explain why we '
        'are not going to comply, because the explanation is worse than the '
        'fine. Keep the carrier up. Pay whatever they ask.',
    sign: 'H. BRENNAN',
  ),
  StationDoc(
    kind: DocKind.letter,
    head: 'LETTER — POSTMARKED 2 AUGUST 1987',
    body: 'You are still on. I checked. My set has been in the loft since my '
        'wife passed and I got it down because I could hear it through the '
        'ceiling. It is not plugged in. I would like someone to come and take '
        'it away and I would like them to come in the daytime.',
  ),
  StationDoc(
    kind: DocKind.transcript,
    head: 'OFF-AIR RECORDING — 05:51, DATE ILLEGIBLE',
    body: '"How long has he been on the roster."\n'
        '"Since the beginning."\n'
        '"He does not think he has been."\n'
        '"He never does. That is what makes him good at it."',
  ),
  StationDoc(
    kind: DocKind.engineering,
    head: 'MERIDIAN CATHODE LTD — SERVICE BULLETIN, MODEL 7',
    body: 'Owners of the Model 7 are advised that the set has no off switch by '
        'design and that the absence is not a fault. Attempts to fit one have '
        'been made by three separate engineers. Their reports are consistent '
        'and are not reproduced here.',
  ),
  StationDoc(
    kind: DocKind.memo,
    head: 'KBLK-7 — PAYROLL, ANNOTATED IN PENCIL',
    body: 'Night operator, one post, continuous since 1963. Twenty-two names '
        'in twenty-four years. Nineteen resignations, none of them written. '
        'Two retirements, neither of them attended. One still on shift.',
  ),
  StationDoc(
    kind: DocKind.log,
    head: 'A PAGE IN YOUR OWN HANDWRITING THAT YOU DO NOT REMEMBER WRITING',
    body: 'Keep the needle up. It does not care what you broadcast, only that '
        'you are broadcasting. Whoever is reading this: the rundown is a lie '
        'and the quotas are real.',
    sign: 'THE DATE ON IT IS TONIGHT.',
  ),
];

/// How many documents exist in total. The number on the front desk.
int get archiveTotal => kArchive.length;

/// The document recovered on [night], or null before night 2 and after the
/// archive runs out.
///
/// One per night, in order. Deliberately not random: it is a sequence, and a
/// sequence is the thing you come back to finish.
StationDoc? docForNight(int night) {
  final i = night - 2;
  if (i < 0 || i >= kArchive.length) return null;
  return kArchive[i];
}

/// Which night hands over document [i].
int nightForDoc(int i) => i + 2;

bool docFound(GameState s, int night) => s.log[night] ?? false;

/// Everything recovered so far, in order.
List<StationDoc> found(GameState s) {
  final out = <StationDoc>[];
  for (var i = 0; i < kArchive.length; i++) {
    if (docFound(s, nightForDoc(i))) out.add(kArchive[i]);
  }
  return out;
}

int foundCount(GameState s) => found(s).length;

/// The line on the front desk. This is the hook, so it is always visible and
/// always one short of finished until it is not.
String archiveLine(GameState s) {
  final n = foundCount(s);
  if (n >= archiveTotal) {
    return 'THE FILE IS COMPLETE. YOU HAVE READ ALL OF IT.';
  }
  return '$n OF $archiveTotal RECOVERED FROM THE DESK';
}


// ---------------------------------------------------------------------------
// THE PERSONAL FILE
//
// Every contract this game has offered the player has now been withdrawn — the
// safe window turns, the presence comes round the front, the carrier can be
// taken down. One is left, and it is the quietest and the most load-bearing:
// the paperwork is about OTHER PEOPLE. Twenty-two names, all of them finished,
// all of them safely in the past.
//
// This is the page where that stops being true.
//
// It is generated from the player's own save — their nights, their kills,
// their fumbles, the number of times they have taken the lid off — and set in
// the payroll's flat administrative voice, dated 1987, filed as though it has
// been in that drawer for forty years. No jumpscare, no gore, nothing moves.
// It is just the station demonstrating that it has been keeping records.
//
// The specific horror is tense, not content: it is written in the PAST about
// things the player did an hour ago, which leaves exactly one reading, and the
// game never states it.
// ---------------------------------------------------------------------------

/// The night the file turns up. Late enough that the archive's own voice is
/// established and the player has stopped expecting it to be about them.
const int kPersonalFileNight = 12;

String _plural(int n, String one, String many) => n == 1 ? one : many;

/// Built fresh every time it is read, so it is always current — reopening it
/// later shows numbers that have moved on without it ever being rewritten.
StationDoc personalFile(GameState s) {
  final st = s.stats;
  final int errors = st.wrong;
  final int held = s.survived;

  final b = StringBuffer()
    ..writeln('OPERATOR 23. No forwarding address on file.')
    ..writeln()
    ..write('Held the post for $held ')
    ..write(_plural(held, 'night', 'nights'))
    ..write('. Put down ${st.banished} ')
    ..write(_plural(st.banished, 'signature', 'signatures'))
    ..write(', missed ${st.scared}, and made $errors ')
    ..write(_plural(errors, 'error at the desk', 'errors at the desk'))
    ..writeln('.');

  if (st.bestStreak > 2) {
    b
      ..writeln()
      ..writeln('Longest clean run: ${st.bestStreak}. He was proud of that one.');
  }
  if (st.clutch > 0) {
    b
      ..writeln()
      ..write('Answered on the buzzer ${st.clutch} ')
      ..write(_plural(st.clutch, 'time', 'times'))
      ..writeln('. We do not encourage it.');
  }
  if (s.revives > 0) {
    b
      ..writeln()
      ..write('Took the sponsor\'s money ${s.revives} ')
      ..write(_plural(s.revives, 'time', 'times'))
      ..writeln('. It was offered, and it was accepted.');
  }
  // ONE line about the room the reader is actually sitting in, and only when
  // there is something true enough to say. Buried in the middle of a personnel
  // record it reads as an oversight rather than as a trick — which is the only
  // way this lands instead of being a gimmick.
  final wall = wallClockLine(s);
  if (wall != null) {
    b
      ..writeln()
      ..writeln(wall);
  }

  b
    ..writeln()
    ..writeln('He was told the carrier was a lid and he believed it, which is '
        'the part that made him useful.');

  return StationDoc(
    kind: DocKind.memo,
    head: 'KBLK-7 — PERSONNEL, CLOSED FILE — 1987',
    body: b.toString().trimRight(),
    sign: 'THIS FILE WAS CLOSED BEFORE HE APPLIED.',
  );
}

/// One row of THE FILE: the page, the night it was recovered on, and whether
/// the reader has it.
///
/// Built in one place, with the night attached, because the personal file is
/// spliced into the middle and any code doing its own index arithmetic around
/// that would silently mislabel every page after it.
typedef FileRow = ({StationDoc doc, int night, bool found, bool isSelf});

/// The archive INCLUDING the page about the reader, once they are far enough
/// in. Everything that lists the file reads this.
List<FileRow> fileRows(GameState s) {
  final out = <FileRow>[];
  final bool self = personalFileOpen(s);
  // slotted among the others rather than appended, so it does not read as a
  // reward screen bolted on the end
  final int at = kArchive.length ~/ 2;
  for (var i = 0; i < kArchive.length; i++) {
    if (self && i == at) {
      out.add((doc: personalFile(s), night: -1, found: true, isSelf: true));
    }
    final n = nightForDoc(i);
    out.add((doc: kArchive[i], night: n, found: docFound(s, n), isSelf: false));
  }
  return out;
}

/// Is the page about the reader open to them yet?
bool personalFileOpen(GameState s) => s.survived >= kPersonalFileNight;
