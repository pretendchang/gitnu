library GitnuTerminal;

import 'dart:html';
import 'dart:async';
import 'dart:math';
import 'statictoolkit.dart';

class GitnuTerminal {
  String _cmdLineContainer;
  String _outputContainer;
  String _cmdLineInput;
  String _container;
  OutputElement _output;
  InputElement _input;
  DivElement _cmdLine;
  DivElement _containerDiv;
  String _version = '0.0.1';
  List<String> _history = [];
  int _historyPosition = 0;
  Map<String, Function> _cmds;
  Map<String, Function> _extCmds;

  GitnuTerminal(this._cmdLineContainer, this._outputContainer,
      this._cmdLineInput, this._container) {
    _cmdLine = document.querySelector(_cmdLineContainer);
    _output = document.querySelector(_outputContainer);
    _input = document.querySelector(_cmdLineInput);
    _containerDiv = document.querySelector(_container);

    // Always force text cursor to end of input line.
    window.onClick.listen((event) => _cmdLine.focus());

    // Trick: Always force text cursor to end of input line.
    _cmdLine.onClick.listen((event) => _input.value = _input.value);

    // Handle up/down key presses for shell history and enter for new command.
    _cmdLine.onKeyDown.listen(historyHandler);
    _cmdLine.onKeyDown.listen(processNewCommand);

    // Handles pgUp, pgDown, end and home scrolling
    _containerDiv.onKeyDown.listen(positionHandler);

    // Ensures the terminal covers the correct height
    int topMargin = 54;
    int bodyHeight = window.innerHeight;
    _containerDiv.style.maxHeight = "${bodyHeight - topMargin}px";
    _containerDiv.style.height = "${bodyHeight - topMargin}px";

  }

  /**
   * Handles scrolling using pgUp, pgDown, end and home keys.
   */
  void positionHandler(KeyboardEvent event) {
    const int pgDownKey = 34;
    const int pgUpKey = 33;
    const int endKey = 35;
    const int homeKey = 36;

    if (event.keyCode == pgDownKey || event.keyCode == pgUpKey ||
        event.keyCode == endKey || event.keyCode == homeKey) {
      event.preventDefault();
      switch(event.keyCode) {
        case pgUpKey:
          _containerDiv.scrollByLines(-5);
          break;
        case pgDownKey:
          _containerDiv.scrollByLines(5);
          break;
        case endKey:
          _cmdLine.scrollIntoView(ScrollAlignment.TOP);
          break;
        case homeKey:
          _output.scrollIntoView(ScrollAlignment.TOP);
          break;
      }
    }
  }

  /**
   * Handles command input
   * Dispatches a function call either to commandFromList(cmd, args)
   * or commandFromExternalList(cmd, ouputWriter, args) where appropriate.
   */
  void processNewCommand(KeyboardEvent event) {
    int enterKey = 13;
    int tabKey = 9;

    if (event.keyCode == tabKey) {
      event.preventDefault();
    } else if (event.keyCode == enterKey) {
      if (!_input.value.isEmpty) {
        _history.add(_input.value);
        _historyPosition = _history.length;
      }

      // Move the line to output and remove id's.
      DivElement line = _input.parent.parent.clone(true);
      line.attributes.remove('id');
      line.classes.add('line');
      InputElement cmdInput = line.querySelector(_cmdLineInput);
      cmdInput.attributes.remove('id');
      cmdInput.autofocus = false;
      cmdInput.readOnly = true;
      _output.children.add(line);
      String cmdline = _input.value;
      _input.value = ""; // clear input

      // Parse out command, args, and trim off whitespace.
      List<String> args;
      String cmd = "";
      if (!cmdline.isEmpty) {
        cmdline.trim();
        args = cmdline.split(' ');
        cmd = args[0];
        args.removeRange(0, 1);
        
        // Special fix for using "" around string params.
        int i = 0;
        int open = -1;
        while (i < args.length) {
          if (open == -1 && args[i].startsWith('"')) {
            args[i] = args[i].substring(1);
            open = i;
            if (args[i].endsWith('"')) {
              args[i] = args[i].substring(0, args[i].length - 1);
              open = -1;
            }
            i++;
          } else if (open != -1 && args[i].endsWith('"')) {
            String pop = args.removeAt(i);
            args[open] = args[open] + " " + pop.substring(0, pop.length - 1);
            open = -1;
          } else if (open != -1) {
            args[open] = args[open] + " " + args.removeAt(i);
          } else {
            i++;
          }
        }
        
        // Unfinished "" set.
        if (open != -1) {
          writeOutput('${StaticToolkit.htmlEscape(cmd)}: unfinished "" set.');
          window.scrollTo(0, window.innerHeight);
          _cmdLine.scrollIntoView(ScrollAlignment.TOP);
          return;
        }
      }

      // Function look up
      if (_cmds[cmd] is Function) {
        _cmds[cmd](cmd, args);
      } else if (_extCmds[cmd] is Function) {
        // Pass our output writing function to the parent function.
        _extCmds[cmd](args);
      } else {
        writeOutput('${StaticToolkit.htmlEscape(cmd)}: command not found');
      }

      window.scrollTo(0, window.innerHeight);

      // Ensures scrolls to prompt line even if no output recorded.
      _cmdLine.scrollIntoView(ScrollAlignment.TOP);
    }
  }

  /**
   * Handles commands entered previously and redisplaying them in the input
   * field when the up and down arrows are used.
   */
  void historyHandler(KeyboardEvent event) {
    int upArrowKey = 38;
    int downArrowKey = 40;

    if (event.keyCode == upArrowKey || event.keyCode == downArrowKey) {
      event.preventDefault();

      if (_historyPosition < _history.length) {
        _history[_historyPosition] = _input.value;
      }
    }

    if (event.keyCode == upArrowKey) {
      _historyPosition--;
      if (_historyPosition < 0) {
        _historyPosition = 0;
      }
    } else if (event.keyCode == downArrowKey) {
      _historyPosition++;
      if (_historyPosition >= _history.length) {
        _historyPosition = max(0, _history.length - 1);
      }
    }

    if (event.keyCode == upArrowKey || event.keyCode == downArrowKey) {
      if (_history.length != 0 && _history[_historyPosition] != null) {
        _input.value = _history[_historyPosition];
      }
    }
  }

  /**
   * Establishes commands that can be called from the terminal and prints a
   * welcome note. Accepts a map of user commands to be called.
   */
  void initialiseCommands(Map<String, Function> commandList) {
    _cmds = {
      'clear': clearCommand,
      'help': helpCommand,
      'version': versionCommand,
      'date': dateCommand,
      'who': whoCommand
    };

    // User added commands
    _extCmds = commandList;

    // Somewhat importantly, print out a welcome header.
    // Headers are slightly mangled below due to escaped characters.
    var rng = new Random();
    int choice = rng.nextInt(3);

    if (choice == 0) {
      writeOutput('<pre class="logo">'
        '           ######   #### ######## ##    ## ##     ## <br>'
        '          ##    ##   ##     ##    ###   ## ##     ## <br>'
        '          ##         ##     ##    ####  ## ##     ## <br>'
        '          ##   ####  ##     ##    ## ## ## ##     ## <br>'
        '          ##    ##   ##     ##    ##  #### ##     ## <br>'
        '          ##    ##   ##     ##    ##   ### ##     ## <br>'
        '           ######   ####    ##    ##    ##  #######  </pre>');
    } else if (choice == 1) {
      writeOutput('<pre class="logo">'
      '      ___                           ___         ___      <br>'
      '     /  /\\      ___         ___    /__/\\       /__/\\     <br>'
      '    /  /:/_    /  /\\       /  /\\   \\  \\:\\      \\  \\:\\    <br>'
      '   /  /:/ /\\  /  /:/      /  /:/    \\  \\:\\      \\  \\:\\   <br>'
      '  /  /:/_/::\\/__/::\\     /  /:/ _____\\__\\:\\ ___  \\  \\:\\  <br>'
      ' /__/:/__\\/\\:\\__\\/\\:\\__ /  /::\\/__/::::::::/__/\\  \\__\\:\\ <br>'
      ' \\  \\:\\ /~~/:/  \\  \\:\\//__/:/\\:\\  \\:\\~~\\~~\\\\  \\:\\ /  /:/ '
          '<br>'
      '  \\  \\:\\  /:/    \\__\\::\\__\\/  \\:\\  \\:\\  ~~~ \\  \\:\\  /:/  '
          '<br>'
      '   \\  \\:\\/:/     /__/:/     \\  \\:\\  \\:\\      \\  \\:\\/:/   <br>'
      '    \\  \\::/      \\__\\/       \\__\\/\\  \\:\\      \\  \\::/    <br>'
      '     \\__\\/                         \\__\\/       \\__\\/     '
      '</pre>');
    } else if (choice == 2) {
      writeOutput('<pre class="logo">'
      '      .-_\'\'\'-.  .-./`) ,---------. ,---.   .--.  ___    _  <br>'
      '     \'_( )_   \\ \\ .-.\')\\          \\|    \\  |  |.\'   |  | | <br>'
      '    |(_ o _)|  \'/ `-\' \\ `--.  ,---\'|  ,  \\ |  ||   .\'  | | <br>'
      '    . (_,_)/___| `-\'`"`    |   \\   |  |\\_ \\|  |.\'  \'_  | | <br>'
      '    |  |  .-----..---.     :_ _:   |  _( )_\\  |\'   ( \\.-.| <br>'
      '    \'  \\  \'-   .\'|   |     (_I_)   | (_ o _)  |\' (`. _` /| <br>'
      '     \\  `-\'`   | |   |    (_(=)_)  |  (_,_)\\  || (_ (_) _) <br>'
      '      \\        / |   |     (_I_)   |  |    |  | \\ /  . \\ / <br>'
      '       `\'-...-\'  \'---\'     \'---\'   \'--\'    \'--\'  ``-\'`-\'\'  '
      '</pre>');
    } else if (choice == 3) {
      writeOutput('<pre class="logo">'
      '         _/_/_/  _/    _/                        <br>'
      '      _/            _/_/_/_/  _/_/_/    _/    _/ <br>'
      '     _/  _/_/  _/    _/      _/    _/  _/    _/  <br>'
      '    _/    _/  _/    _/      _/    _/  _/    _/   <br>'
      '     _/_/_/  _/      _/_/  _/    _/    _/_/_/    '
      '</pre>');
    }

    writeOutput('<div>Welcome to Gitnu! (v$_version)</div>');
    writeOutput(new DateTime.now().toLocal().toString());
    writeOutput('<p>Documentation: type "help"</p>');
    writeOutput('<p>Initialise a root directory to begin.</p>');
  }

  /**
   * Wraps around the StaticToolkit writer function as we have access to the
   * output stream and cmdLine element here.
   */
  void writeOutput(String h) {
    StaticToolkit.writeOutput(h, _output, _cmdLine);
  }

  /**
   * Basic inbuilt commands.
   * User function invariant (except help... builds off user functions).
   */
  void clearCommand(String cmd, List<String> args) {
    _output.innerHtml = '';
  }

  void helpCommand(String cmd, List<String> args) {
    StringBuffer sb = new StringBuffer();
    sb.write('<div class="ls-files">');
    _cmds.keys.forEach((key) => sb.write('$key<br>'));
    _extCmds.keys.forEach((key) => sb.write('$key<br>'));
    sb.write('</div>');
    writeOutput(sb.toString());
  }

  void versionCommand(String cmd, List<String> args) {
    writeOutput("$_version");
  }

  void dateCommand(String cmd, var args) {
    writeOutput(new DateTime.now().toLocal().toString());
  }

  void whoCommand(String cmd, List<String> args) {
    writeOutput('${StaticToolkit.htmlEscape(document.title)}<br>'
        'Basic terminal implementation - By:  Eric Bidelman '
        '&lt;ericbidelman@chromium.org&gt;, Adam Singer '
        '&lt;financeCoding@gmail.com&gt;<br>Adapted by Cameron Fitzgerald '
        '&lt;camfitz@google.com|camandco@gmail.com&gt; for Git / advanced '
        'features.');
  }
}