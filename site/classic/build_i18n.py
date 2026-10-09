"""Build the bilingual site: src/*.html are the Russian pages; every text gets an English twin.

Both languages live in the page as <x-l lang="ru"> / <x-l lang="en">; CSS shows one of them,
a small script remembers the choice. English is the default.
"""
import os
import re

T = {
    # --- shared ---
    'Возможности': 'Features',
    'Безопасность': 'Security',
    'Скачать': 'Download',
    'Открытый код, AGPL-3.0 · основано на Night Drop · ': 'Open source, AGPL-3.0 · based on Night Drop · ',
    'исходники': 'source',
    'Скачать для Android': 'Download for Android',
    'Скачать для Windows': 'Download for Windows',
    # --- home ---
    'Анонимный мессенджер для личных разговоров и небольших групп.': 'An anonymous messenger for private conversations and small groups.',
    'Без номера телефона. Без имени. Без профиля.': 'No phone number. No name. No profile.',
    'Сквозное шифрование': 'End-to-end encryption',
    'Сообщения шифруются на устройстве и доступны только участникам разговора.':
        'Messages are encrypted on your device and can be read only by the people in the conversation.',
    'Без аккаунта': 'No account',
    'Ни номера телефона, ни почты, ни логина.': 'No phone number, no email, no login.',
    'Только свои': 'Only people you know',
    'Личные чаты и группы до 10 человек. Никаких каналов и публичных чатов.': 'One-to-one chats and groups of up to 10. No channels, no public chats.',
    # --- download ---
    'Бесплатно и без регистрации. Выберите устройство — установка занимает пару минут.':
        'Free, no sign-up. Pick your device — installing takes a couple of minutes.',
    'Телефон или планшет': 'Phone or tablet',
    'Компьютер': 'Computer',
    'APK · 39 МБ': 'APK · 39 MB',
    'Для старых телефонов (32-бит)': 'For older phones (32-bit)',
    'Если основной файл не устанавливается, телефон, скорее всего, 32-битный. <a data-file="android-armv7" href="cyberdog-0.1.27-b68-armv7.apk" download>Скачать версию для старых телефонов · 32 МБ</a>':
        'If the main file will not install, the phone is most likely 32-bit. <a data-file="android-armv7" href="cyberdog-0.1.27-b68-armv7.apk" download>Download the version for older phones · 32 MB</a>',
    'Установщик · 20 МБ': 'Installer · 20 MB',
    'Windows 10 и 11': 'Windows 10 and 11',
    'Нажмите <b>«Скачать для Android»</b> и дождитесь окончания загрузки.':
        'Tap <b>“Download for Android”</b> and wait for the download to finish.',
    'Откройте файл из уведомления или из папки «Загрузки».':
        'Open the file from the notification or from your Downloads folder.',
    'Если Android спросит, разрешите браузеру <b>установку из этого источника</b> и вернитесь назад.':
        'If Android asks, allow your browser to <b>install from this source</b>, then go back.',
    'Нажмите <b>«Установить»</b>, затем <b>«Открыть»</b>.': 'Tap <b>“Install”</b>, then <b>“Open”</b>.',
    'Начиная со сборки 31 обновления ставятся поверх установленной версии. Если у вас сборка 30 или старше, один раз удалите её перед установкой — вместе с ней удаляются личность и переписка на этом устройстве.':
        'From build 31 on, updates install over the version you already have. If you have build 30 or older, uninstall it once before installing — your identity and conversations on this device are removed with it.',
    'Контрольная сумма SHA-256': 'SHA-256 checksum',
    'Нажмите <b>«Скачать для Windows»</b>.': 'Click <b>“Download for Windows”</b>.',
    'Браузер может предупредить, что файл скачивают редко, — выберите <b>«Сохранить»</b>. В Microsoft Edge эта кнопка спрятана: стрелка рядом с «Удалить» → <b>«Сохранить всё равно»</b>.':
        'Your browser may warn that the file is not commonly downloaded — choose <b>“Keep”</b>. In Microsoft Edge the option is tucked away: the arrow next to “Delete” → <b>“Keep anyway”</b>.',
    'Запустите файл. В синем окне Windows нажмите <b>«Подробнее»</b>, затем <b>«Выполнить в любом случае»</b>.':
        'Run the file. In the blue Windows dialog click <b>“More info”</b>, then <b>“Run anyway”</b>.',
    'Пройдите установщик — права администратора не нужны. Приложение появится в меню «Пуск».':
        'Go through the installer — no administrator rights needed. The app appears in the Start menu.',
    'Установщик пока не подписан, поэтому Windows показывает предупреждения. Если включено «Интеллектуальное управление приложениями» (Smart App Control), Windows 11 не даст запустить программу. Выключить его можно так: <b>Безопасность Windows → Управление приложениями и браузером → Параметры интеллектуального управления приложениями → Выкл.</b> Включить обратно получится только переустановкой Windows, поэтому решайте сами — либо пользуйтесь версией для Android.':
        'The installer is not signed yet, so Windows shows warnings. If Smart App Control is on, Windows 11 will not let the program run at all. To turn it off: <b>Windows Security → App &amp; browser control → Smart App Control settings → Off.</b> It can only be turned back on by reinstalling Windows, so decide for yourself — or use the Android version.',
    'ПЕРВЫЙ ЗАПУСК': 'FIRST LAUNCH',
    'Как начать переписку': 'How to start a conversation',
    'Нажмите <b>«Создать мою личность»</b>. Ни регистрации, ни телефона, ни почты.':
        'Tap <b>“Create my identity”</b>. No sign-up, no phone number, no email.',
    'Один из вас открывает <b>«Новый чат» → «Пригласить»</b>: появится QR и короткий код.':
        'One of you opens <b>“New chat” → “Invite”</b>: a QR code and a short code appear.',
    'Второй открывает <b>«Новый чат» → «Присоединиться»</b> и сканирует QR или вводит код.':
        'The other opens <b>“New chat” → “Join”</b> and scans the QR or types the code.',
    'Чат устанавливается сам. Можно писать и отправлять фото и видео.':
        'The chat sets itself up. You can write and send photos and videos.',
    'Откройте <b>«Проверить код безопасности»</b>, сверьте цифры и отметьте чат проверенным.':
        'Open <b>“Verify safety number”</b>, compare the digits and mark the chat verified.',
    'Передавайте код приглашения только тому, с кем хотите общаться, и по каналу, которому доверяете: тот, кто введёт код, сразу попадёт в чат.':
        'Share the invite code only with the person you want to talk to, over a channel you trust: whoever enters the code is in the chat straight away.',
    # --- security ---
    'Безопасность CyberDog': 'CyberDog Security',
    'Приватность должна работать автоматически.': 'Privacy should work on its own.',
    'CyberDog защищает переписку без номера телефона, почты и публичного профиля.':
        'CyberDog protects your conversations without a phone number, an email address or a public profile.',
    'Сообщения шифруются на вашем устройстве и расшифровываются только у собеседника.':
        'Messages are encrypted on your device and decrypted only on the other person’s.',
    'Без телефона и email': 'No phone, no email',
    'Для общения не требуется привязывать номер телефона, почту или настоящее имя.':
        'You never have to link a phone number, an email address or your real name.',
    'Проверка собеседника': 'Verify who you talk to',
    'Сравните код безопасности или QR-код, чтобы убедиться, что разговариваете именно с нужным человеком.':
        'Compare the safety number or scan the QR code to be sure you are talking to the right person.',
    'Приватные уведомления': 'Private notifications',
    'В уведомлениях нет текста сообщений: на экране блокировки видно только то, что пришло новое сообщение.':
        'Notifications carry no message text: the lock screen shows only that a new message arrived.',
    'Исчезающие сообщения': 'Disappearing messages',
    'Сообщения можно автоматически удалять после просмотра или через выбранное время.':
        'Messages can be deleted automatically after they are viewed or after a time you choose.',
    'Фото под защитой': 'Protected photos',
    'Входящие изображения скрыты до открытия, а своё фото можно отправить в режиме «Посмотреть один раз».':
        'Incoming pictures stay hidden until you open them, and your own photo can be sent as “View once”.',
    'Минимум данных на сервере': 'Minimal data on the server',
    'Сервер только доставляет зашифрованные сообщения и хранит их не дольше суток, пока собеседник не выйдет на связь. Прочитать их он не может: ключи есть только на ваших устройствах. Как любой сервер в интернете, он видит адрес подключения и время.':
        'The server only delivers encrypted messages and keeps them for no more than a day, until the other person comes online. It cannot read them: the keys exist only on your devices. Like any server on the internet, it sees the connecting address and the time.',
    'Ваш разговор принадлежит вам, а не сервису.': 'Your conversation belongs to you, not to the service.',
    'Что CyberDog не может контролировать': 'What CyberDog cannot control',
    'CyberDog не может запретить собеседнику сфотографировать экран другим устройством или сохранить уже увиденную информацию.':
        'CyberDog cannot stop the other person from photographing the screen with another device or keeping what they have already seen.',
    'Защита работает внутри приложения и при передаче данных, но не может контролировать действия человека после просмотра сообщения.':
        'Protection works inside the app and while data travels, but it cannot control what a person does after reading a message.',
    'Технические подробности': 'Technical details',
}

# Texts with numbers that change with every build.
PATTERNS = [
    (r'Beta · Android: ([\d.]+), сборка (\d+) · Windows: ([\d.]+), сборка (\d+)',
     r'Beta · Android: \1, build \2 · Windows: \3, build \4'),
    (r'Версия ([\d.]+) · сборка (\d+)', r'Version \1 · build \2'),
]

TITLES = {
    'index.html': ('CYBERDOG — anonymous messenger', 'CYBERDOG — анонимный мессенджер'),
    'download.html': ('Download CYBERDOG — Android and Windows', 'Скачать CYBERDOG — Android и Windows'),
    'security.html': ('CYBERDOG Security', 'Безопасность CYBERDOG'),
}
DESCRIPTIONS = {
    'index.html': 'CYBERDOG is a messenger for private conversations and small groups, with end-to-end encryption. No phone number, no name, no profile.',
    'download.html': 'Download CYBERDOG for Android and Windows, with step-by-step installation.',
    'security.html': 'How CYBERDOG protects conversations: end-to-end encryption, no phone or email, contact verification, disappearing messages.',
}

CSS = '''  x-l { display: inline; }
  html[data-lang="en"] x-l[lang="ru"], html[data-lang="ru"] x-l[lang="en"] { display: none; }
  .lang { display: inline-flex; gap: 5px; padding: 6px 10px; border: 1px solid var(--border); border-radius: 10px; background: none;
    color: var(--muted); font: 600 12px/1 inherit; letter-spacing: .08em; cursor: pointer; }
  .lang:hover { border-color: var(--border-on); }
  html[data-lang="en"] .lang b:first-child, html[data-lang="ru"] .lang b:last-child { color: var(--accent-l); }
  .lang b { font-weight: 600; }
'''
MOBILE_OLD = 'nav a:first-child { display: none; }'
MOBILE_NEW = 'nav a:not(.pill) { display: none; }'


def pair(ru, en):
    return f'<x-l lang="ru">{ru}</x-l><x-l lang="en">{en}</x-l>'


def build(name):
    s = open(os.path.join('src', name), encoding='utf-8').read()
    for ru in sorted(T, key=len, reverse=True):
        s = re.sub(r'>(\s*)' + re.escape(ru) + r'(\s*)<', lambda m, ru=ru: '>' + m.group(1) + pair(ru, T[ru]) + m.group(2) + '<', s)
    for pat, rep in PATTERNS:
        s = re.sub(r'>(\s*)(' + pat + r')(\s*)<',
                   lambda m, pat=pat, rep=rep: '>' + m.group(1) + pair(m.group(2), re.sub(pat, rep, m.group(2))) + m.group(m.lastindex) + '<', s)

    en_title, ru_title = TITLES[name]
    script = ("<script>(function(){var d=document.documentElement,k='cyberdog-lang',t={en:%r,ru:%r},l;"
              "try{l=localStorage.getItem(k)}catch(e){}"
              "function set(n){d.dataset.lang=n;d.lang=n;document.title=t[n]}"
              "set(l==='ru'?'ru':'en');"
              "document.addEventListener('click',function(e){if(!e.target.closest('.lang'))return;"
              "var n=d.dataset.lang==='en'?'ru':'en';set(n);try{localStorage.setItem(k,n)}catch(e){}})})();</script>\n"
              % (en_title, ru_title))
    s = s.replace('<html lang="ru">', '<html lang="en" data-lang="en">', 1)
    s = re.sub(r'<title>[^<]*</title>', '<title>' + en_title + '</title>\n' + script.rstrip('\n'), s, count=1)
    s = re.sub(r'(<meta name="description" content=")[^"]*(">)', lambda m: m.group(1) + DESCRIPTIONS[name] + m.group(2), s, count=1)
    assert s.count('</style>') == 1
    s = s.replace('</style>', CSS + '</style>')
    # header: the switch sits after the Download button
    s, n = re.subn(r'(<a class="pill[^"]*" href="download\.html">.*?</a>)',
                   r'\1\n    <button class="lang" type="button" aria-label="Language"><b>EN</b><span>/</span><b>RU</b></button>', s, count=1, flags=re.S)
    assert n == 1, name
    # phones: the header keeps Download and the switch; the other pages are linked from the footer
    assert s.count(MOBILE_OLD) == 1, name
    s = s.replace(MOBILE_OLD, MOBILE_NEW)
    footer = pair('Безопасность', 'Security')
    s, n = re.subn(r'(<p class="legal">)', r'\1<a href="security.html">' + footer + '</a> · ', s, count=1)
    assert n == 1, name

    # anything Russian left outside a ru block is an untranslated string
    visible = re.sub(r'<x-l lang="ru">.*?</x-l>', '', s, flags=re.S)
    visible = re.sub(r'<script>.*?</script>', '', visible, flags=re.S)
    left = sorted(set(re.findall(r'>([^<>]*[А-Яа-яЁё][^<>]*)<', visible)))
    open(name, 'w', encoding='utf-8', newline='\n').write(s)
    return left


if __name__ == '__main__':
    for page in ('index.html', 'download.html', 'security.html'):
        missing = build(page)
        print(page, 'untranslated:', missing)
