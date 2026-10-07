import 'app_locale.dart';

/// In-chat system notices are written by the core in English and stored in the chat history as
/// plain text, so they are translated here, at display time. That keeps old history readable in
/// whichever language is selected now, and leaves the stored text and the wire format untouched.
///
/// Each entry is a distinctive fragment of the English notice and its Russian wording.
const _notices = <(String, String)>[
  (
    're-paired with a new secure session. Your earlier',
    'Собеседник выполнил сопряжение заново, начата новая защищённая сессия. Прежняя проверка '
        'больше не действует — сверьте код безопасности ещё раз, прежде чем доверять этому чату.',
  ),
  (
    're-paired, starting a new secure session',
    'Собеседник выполнил сопряжение заново, начата новая защищённая сессия. Сверьте код '
        'безопасности, если хотите убедиться, что это он.',
  ),
  (
    'Re-paired with a new secure session',
    'Сопряжение выполнено заново, начата новая защищённая сессия. Сверьте код безопасности ещё '
        'раз, если хотите убедиться, кто это.',
  ),
  (
    'enabled 24h server storage',
    'Собеседник включил хранение на сервере на 24 ч для этого чата. Сообщения хранятся на '
        'ретрансляторе в зашифрованном виде до 24 часов.',
  ),
  (
    'disabled server storage',
    'Собеседник выключил хранение на сервере для этого чата. Сообщения остаются только на '
        'ваших устройствах.',
  ),
  ('Your chat request was approved', 'Ваш запрос на чат одобрен. Можно начинать общение.'),
  (
    'invite code has already been used',
    'Этот код приглашения уже использован. Попросите новый код, чтобы начать чат.',
  ),
  (
    'deleted this chat',
    'Собеседник удалил этот чат. Чтобы продолжить общение, нужно создать новый чат.',
  ),
  ('took a screenshot of this chat', 'Собеседник сделал скриншот этого чата.'),
  ('You took a screenshot', 'Вы сделали скриншот. Собеседнику об этом сообщили.'),
  (
    'keeping a backup of this chat',
    'Собеседник хранит резервную копию этого чата, поэтому ваши сообщения могут оставаться в '
        'его копии.',
  ),
  (
    'safety number verified',
    'Собеседник отметил код безопасности этого чата как проверенный. Сверьте его и сами, чтобы '
        'убедиться — это лишь то, что вам сообщили.',
  ),
  (
    'cleared their verification',
    'Собеседник снял отметку о проверке кода безопасности этого чата.',
  ),
  (
    'connection address changed',
    'Адрес подключения собеседника изменился; сообщения будут доходить, как и раньше.',
  ),
  (
    'Waiting for the other person to accept',
    'Ждём, пока собеседник примет чат. Сообщения не будут доставлены, пока он не примет.',
  ),
];

final _timer =
    RegExp(r'^(\S+ )?(You|The other person) set disappearing messages to (.+)\.$');
final _span = RegExp(r'^(\d+) (week|day|hour|minute|second)\(s\)$');
const _units = {'week': 'нед.', 'day': 'дн.', 'hour': 'ч', 'minute': 'мин', 'second': 'с'};

/// The notice as it should be shown in the current language.
String localizeSystemNotice(String text) {
  if (AppLocale.current.value != AppLocale.russian) return text;

  final timer = _timer.firstMatch(text);
  if (timer != null) {
    final who = timer.group(2) == 'You' ? 'Вы установили' : 'Собеседник установил';
    return '${timer.group(1) ?? ''}$who исчезающие сообщения: ${_duration(timer.group(3)!)}.';
  }
  for (final (fragment, russian) in _notices) {
    if (text.contains(fragment)) return '${_marker(text)}$russian';
  }
  return text;
}

String _duration(String label) {
  if (label == 'off') return 'выкл';
  final span = _span.firstMatch(label);
  return span == null ? label : '${span.group(1)} ${_units[span.group(2)]}';
}

/// The leading pictogram of the original notice, kept so the two languages look alike.
String _marker(String text) {
  final first = text.split(' ').first;
  return first.isNotEmpty && first.codeUnitAt(0) > 127 ? '$first ' : '';
}
