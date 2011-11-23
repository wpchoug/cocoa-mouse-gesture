Requirements:

1. Max OS X 10.6+ (tested in 10.7.2)
2. Xcode 4.2+


Fetures:

1. Recognize mouse gesture in 4 directions: left, right, up and down.
2. Handle mouse gestures in 3 ways:
 1) Send keystroke.
 2) Type text.
 3) Click button via accessibility API.
3. Temporarily disable / enable.
4. Lanch at login.


Predefined gestures:

1. ↑	go to top
2. ↓	go to bottom
3. ←	change to left space
4. →	change to right space
5. ↑↓	page up
6. ↓↑	page down
7. →↓	close window / tab.
8. →↑	reopen last closed tab
9. ←↓	minimize
10. ←↑	zoom
11. ↑→	switch full screen mode
12. ↓←	print user name
13. ↓→	print password
14. ↓←↑	print email


Configuration:

1. Open MouseGesture.app/Contents/Resources/Localizable.strings, set your own name, password and email address.
2. Check "Enable access for assistive devices" in Universal Access Preferences.
3. If you want customize gestures or extend it, open the project in Xcode.