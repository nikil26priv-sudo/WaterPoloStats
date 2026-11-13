'use strict';
// Pure game logic: no DOM here, so it can be tested on its own.
// Data uses the same shape and encodings as the iPad app (dates are seconds since 2001-01-01),
// so a games file exported from one opens in the other.

var WP = globalThis.WP || (globalThis.WP = {});

(function () {
  var APPLE_EPOCH = 978307200;
  var REGULATION = 4;

  function appleNow(ms) {
    return (ms === undefined ? Date.now() : ms) / 1000 - APPLE_EPOCH;
  }

  function toDate(apple) {
    return new Date((apple + APPLE_EPOCH) * 1000);
  }

  function fromDate(date) {
    return date.getTime() / 1000 - APPLE_EPOCH;
  }

  function uid() {
    if (globalThis.crypto && crypto.randomUUID) return crypto.randomUUID().toUpperCase();
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
      var r = (Math.random() * 16) | 0;
      return (c === 'x' ? r : (r & 3) | 8).toString(16);
    }).toUpperCase();
  }

  // ---- Players

  var POSITIONS = [
    { id: 'goalkeeper', short: 'GK', title: 'GK - Goalkeeper' },
    { id: 'center', short: 'C', title: 'C - Center' },
    { id: 'centerBack', short: 'CB', title: 'CB - Center Back' },
    { id: 'driver', short: 'D', title: 'D - Driver' },
    { id: 'wing', short: 'W', title: 'W - Wing' },
    { id: 'point', short: 'P', title: 'P - Point' },
    { id: 'utility', short: 'U', title: 'U - Utility' },
  ];

  function position(id) {
    return POSITIONS.find(function (p) { return p.id === id; }) || POSITIONS[3];
  }

  function newPlayer(capNumber) {
    return { id: uid(), firstName: '', lastName: '', capNumber: capNumber || 1, position: 'driver', isArchived: false };
  }

  function isGoalie(player) { return !!player && player.position === 'goalkeeper'; }

  function playerName(player) {
    return [player.firstName, player.lastName].filter(Boolean).join(' ');
  }

  function shortName(player) {
    if (!player.lastName) return player.firstName || '#' + player.capNumber;
    if (!player.firstName) return player.lastName;
    return player.lastName + ' ' + player.firstName[0] + '.';
  }

  function playerLabel(player) {
    var name = playerName(player);
    return name ? '#' + player.capNumber + ' ' + name : '#' + player.capNumber;
  }

  function heightText(player) {
    if (player.heightCm == null) return '–';
    var inches = Math.round(player.heightCm / 2.54);
    return player.heightCm + ' cm / ' + Math.floor(inches / 12) + '-' + (inches % 12);
  }

  function weightText(player) {
    if (player.weightKg == null) return '–';
    return player.weightKg + ' kg / ' + Math.round(player.weightKg * 2.2046) + ' lbs';
  }

  // ---- Games and the clock

  function newGame(props) {
    var game = {
      id: uid(), date: appleNow(), teamName: '', opponent: '', location: '', league: '', isHome: true,
      notes: '', sketches: [], periodLength: 480, overtimeLength: 180, exclusionLength: 20,
      rosterIDs: [], events: [], period: 1, clock: 480, isFinal: false,
    };
    Object.assign(game, props || {});
    if (!props || props.clock === undefined) game.clock = game.periodLength;
    return game;
  }

  function periodName(period) {
    return period <= REGULATION ? 'Q' + period : 'OT' + (period - REGULATION);
  }

  function lengthOf(game, period) {
    return period <= REGULATION ? game.periodLength : game.overtimeLength;
  }

  function isRunning(game) { return game.runningSince != null; }

  function remaining(game, nowMs) {
    if (game.runningSince == null) return game.clock;
    return Math.max(0, game.clock - (appleNow(nowMs) - game.runningSince));
  }

  function clockSeconds(game, nowMs) { return Math.ceil(remaining(game, nowMs) - 1e-9); }

  function startClock(game, nowMs) {
    if (game.runningSince != null || game.clock <= 0) return;
    game.runningSince = appleNow(nowMs);
  }

  function stopClock(game, nowMs) {
    game.clock = remaining(game, nowMs);
    delete game.runningSince;
  }

  function adjustClock(game, delta, nowMs) {
    var wasRunning = isRunning(game);
    stopClock(game, nowMs);
    game.clock = Math.min(lengthOf(game, game.period), Math.max(0, game.clock + delta));
    if (wasRunning) startClock(game, nowMs);
  }

  function resetClock(game) {
    delete game.runningSince;
    game.clock = lengthOf(game, game.period);
  }

  function goToPeriod(game, period) {
    if (period === game.period) return;
    game.period = period;
    resetClock(game);
  }

  /** The same game with only one period's events (5 means all overtime). */
  function filtered(game, period) {
    if (period == null) return game;
    var copy = Object.assign({}, game);
    copy.events = game.events.filter(function (e) {
      return period > REGULATION ? e.period > REGULATION : e.period === period;
    });
    return copy;
  }

  function periodsPlayed(game) {
    var last = Math.max(game.period, REGULATION);
    game.events.forEach(function (e) { last = Math.max(last, e.period); });
    var out = [];
    for (var p = 1; p <= last; p++) out.push(p);
    return out;
  }

  // ---- Events

  var KINDS = {
    shot: 'Shot', steal: 'Steal', turnover: 'Turnover', block: 'Field block',
    exclusion: 'Exclusion', exclusionDrawn: 'Exclusion drawn', penaltyFoul: 'Penalty foul', penaltyDrawn: 'Penalty drawn',
    save: 'Save', goalAgainst: 'Opponent goal', sprintWon: 'Sprint won', sprintLost: 'Sprint lost', timeout: 'Timeout',
  };
  var NEEDS_PLAYER = ['shot', 'steal', 'turnover', 'block', 'exclusion', 'exclusionDrawn', 'penaltyFoul', 'penaltyDrawn'];
  var OUTCOMES = { goal: 'Goal', saved: 'Saved', blocked: 'Blocked', missed: 'Missed' };
  var SITUATIONS = ['even', 'powerPlay', 'penalty'];

  function situationTitle(situation, defending) {
    if (situation === 'powerPlay') return defending ? 'Man down' : '6 on 5';
    return situation === 'penalty' ? 'Penalty' : 'Even';
  }

  function needsPlayer(kind) { return NEEDS_PLAYER.indexOf(kind) >= 0; }
  function isPersonalFoul(kind) { return kind === 'exclusion' || kind === 'penaltyFoul'; }
  function isGoal(event) { return event.kind === 'shot' && event.outcome === 'goal'; }

  function logEvent(game, kind, playerID, nowMs) {
    var event = { id: uid(), kind: kind, period: game.period, clock: clockSeconds(game, nowMs), situation: 'even', createdAt: appleNow(nowMs) };
    if (playerID) event.playerID = playerID;
    game.events.push(event);
    return event;
  }

  function goalsFor(game, period) {
    return game.events.filter(function (e) { return isGoal(e) && (period == null || e.period === period); }).length;
  }

  function goalsAgainst(game, period) {
    return game.events.filter(function (e) { return e.kind === 'goalAgainst' && (period == null || e.period === period); }).length;
  }

  function chronological(game) {
    return game.events.slice().sort(function (a, b) {
      return a.period - b.period || b.clock - a.clock || a.createdAt - b.createdAt;
    });
  }

  // ---- Stats

  function emptyLine() {
    return {
      games: 0, goals: 0, shots: 0, assists: 0, steals: 0, turnovers: 0, blocks: 0, exclusions: 0, exclusionsDrawn: 0,
      penaltyFouls: 0, penaltiesDrawn: 0, saves: 0, goalsAgainst: 0, sprintsWon: 0, sprintsLost: 0,
    };
  }

  function count(line, event) {
    switch (event.kind) {
      case 'shot': line.shots++; if (event.outcome === 'goal') line.goals++; break;
      case 'steal': line.steals++; break;
      case 'turnover': line.turnovers++; break;
      case 'block': line.blocks++; break;
      case 'exclusion': line.exclusions++; break;
      case 'exclusionDrawn': line.exclusionsDrawn++; break;
      case 'penaltyFoul': line.penaltyFouls++; break;
      case 'penaltyDrawn': line.penaltiesDrawn++; break;
      case 'save': line.saves++; break;
      case 'goalAgainst': line.goalsAgainst++; break;
      case 'sprintWon': line.sprintsWon++; break;
      case 'sprintLost': line.sprintsLost++; break;
    }
  }

  function addLines(a, b) {
    var out = emptyLine();
    Object.keys(out).forEach(function (key) { out[key] = a[key] + b[key]; });
    return out;
  }

  function personalFouls(line) { return line.exclusions + line.penaltyFouls; }
  function shotPct(line) { return line.shots > 0 ? line.goals / line.shots : null; }
  function savePct(line) {
    var faced = line.saves + line.goalsAgainst;
    return faced > 0 ? line.saves / faced : null;
  }

  /** One line per player who appears in the events. Assists belong to the passer, not the scorer. */
  function playerLines(events) {
    var lines = {};
    function lineFor(id) { return lines[id] || (lines[id] = emptyLine()); }
    events.forEach(function (event) {
      if (event.playerID) count(lineFor(event.playerID), event);
      if (isGoal(event) && event.assistID) lineFor(event.assistID).assists++;
    });
    return lines;
  }

  function teamLine(events) {
    var line = emptyLine();
    events.forEach(function (event) {
      count(line, event);
      if (isGoal(event) && event.assistID) line.assists++;
    });
    return line;
  }

  function gameLines(game) {
    var lines = playerLines(game.events);
    game.rosterIDs.forEach(function (id) { (lines[id] || (lines[id] = emptyLine())).games = 1; });
    return lines;
  }

  function gameTeamLine(game) {
    var line = teamLine(game.events);
    line.games = 1;
    return line;
  }

  function seasonLines(games) {
    var totals = {};
    games.forEach(function (game) {
      var lines = gameLines(game);
      Object.keys(lines).forEach(function (id) {
        totals[id] = addLines(totals[id] || emptyLine(), lines[id]);
      });
    });
    return totals;
  }

  function seasonTeamLine(games) {
    return games.reduce(function (total, game) { return addLines(total, gameTeamLine(game)); }, emptyLine());
  }

  /** Man-up, man-down and penalty numbers for the team. */
  function situationSummary(events) {
    var s = { manUpGoals: 0, manUpChances: 0, manDownGoalsAgainst: 0, manDownChances: 0, penaltyGoals: 0, penaltyShots: 0 };
    events.forEach(function (e) {
      if (e.kind === 'shot') {
        if (e.situation === 'powerPlay' && e.outcome === 'goal') s.manUpGoals++;
        if (e.situation === 'penalty') { s.penaltyShots++; if (e.outcome === 'goal') s.penaltyGoals++; }
      } else if (e.kind === 'exclusionDrawn') s.manUpChances++;
      else if (e.kind === 'exclusion') s.manDownChances++;
      else if (e.kind === 'goalAgainst' && e.situation === 'powerPlay') s.manDownGoalsAgainst++;
    });
    return s;
  }

  function percent(value) { return value == null ? '–' : Math.round(value * 100) + '%'; }
  function percent1(value) { return value == null ? '–' : (value * 100).toFixed(1) + '%'; }
  function clockText(seconds) {
    return Math.floor(seconds / 60) + ':' + String(seconds % 60).padStart(2, '0');
  }

  var COLUMNS = {
    games: { header: 'GP', title: 'Games played', value: function (l) { return l.games; } },
    goals: { header: 'G', title: 'Goals', value: function (l) { return l.goals; } },
    shots: { header: 'Sh', title: 'Shots', value: function (l) { return l.shots; } },
    shotPct: { header: 'Sh%', title: 'Shooting %', value: function (l) { var v = shotPct(l); return v == null ? -1 : v; }, text: function (l) { return percent(shotPct(l)); } },
    assists: { header: 'A', title: 'Assists', value: function (l) { return l.assists; } },
    points: { header: 'Pts', title: 'Points (goals + assists)', value: function (l) { return l.goals + l.assists; } },
    steals: { header: 'Stl', title: 'Steals', value: function (l) { return l.steals; } },
    turnovers: { header: 'TO', title: 'Turnovers', value: function (l) { return l.turnovers; } },
    blocks: { header: 'Blk', title: 'Field blocks', value: function (l) { return l.blocks; } },
    exclusions: { header: 'Ex', title: 'Exclusions and penalty fouls', value: personalFouls },
    exclusionsDrawn: { header: 'DEx', title: 'Exclusions and penalties drawn', value: function (l) { return l.exclusionsDrawn + l.penaltiesDrawn; } },
    saves: { header: 'Sv', title: 'Saves', value: function (l) { return l.saves; } },
    goalsAgainst: { header: 'GA', title: 'Goals against', value: function (l) { return l.goalsAgainst; } },
    savePct: { header: 'Sv%', title: 'Save %', value: function (l) { var v = savePct(l); return v == null ? -1 : v; }, text: function (l) { return percent(savePct(l)); } },
    sprints: { header: 'Spr', title: 'Sprints won-lost', value: function (l) { return l.sprintsWon; }, text: function (l) { return l.sprintsWon + '–' + l.sprintsLost; } },
  };
  Object.keys(COLUMNS).forEach(function (id) { COLUMNS[id].id = id; });

  function columnText(id, line) {
    var column = COLUMNS[id];
    return column.text ? column.text(line) : String(column.value(line));
  }

  var COLUMN_SETS = {
    fieldBox: ['goals', 'shots', 'assists', 'steals', 'turnovers', 'blocks', 'exclusions', 'exclusionsDrawn'],
    goalieBox: ['saves', 'goalsAgainst', 'savePct'],
    basic: ['goals', 'shots', 'assists', 'steals', 'turnovers', 'blocks', 'exclusions', 'games'],
    extended: ['goals', 'shots', 'shotPct', 'assists', 'points', 'steals', 'turnovers', 'blocks', 'exclusions', 'exclusionsDrawn', 'saves', 'goalsAgainst', 'savePct', 'sprints', 'games'],
  };

  /** "Johny Clore - Goal (6 on 5), assist Sam Okafor" or "Hill 2025 - Goal". */
  function playText(event, game, nameOf) {
    var who = event.kind === 'goalAgainst' ? game.opponent : nameOf(event.playerID) || game.teamName || 'Team';
    var what;
    if (event.kind === 'shot') {
      what = event.outcome === 'goal' ? 'Goal' : 'Shot ' + (OUTCOMES[event.outcome] || 'Missed');
      if (event.situation !== 'even') what += ' (' + situationTitle(event.situation) + ')';
      if (event.outcome === 'goal' && event.assistID) what += ', assist ' + (nameOf(event.assistID) || '?');
    } else if (event.kind === 'goalAgainst') {
      what = 'Goal';
      if (event.situation !== 'even') what += ' (' + situationTitle(event.situation) + ')';
    } else {
      what = KINDS[event.kind] || event.kind;
    }
    return who + ' - ' + what;
  }

  // ---- CSV

  function csvText(rows) {
    return rows.map(function (row) {
      return row.map(function (field) {
        field = String(field == null ? '' : field);
        // A leading =, +, - or @ would be run as a formula by spreadsheet apps.
        if (/^[=+\-@]/.test(field)) field = "'" + field;
        return /[",\n]/.test(field) ? '"' + field.replace(/"/g, '""') + '"' : field;
      }).join(',');
    }).join('\r\n') + '\r\n';
  }

  function statsCSV(players, lines, team, columnIDs) {
    function cell(id, line) {
      if (id === 'sprints') return line.sprintsWon + '-' + line.sprintsLost;
      return columnText(id, line).replace('–', '');
    }
    var rows = [['Cap', 'Player'].concat(columnIDs.map(function (id) { return COLUMNS[id].title; }))];
    players.forEach(function (player) {
      var line = lines[player.id] || emptyLine();
      rows.push([player.capNumber, playerName(player)].concat(columnIDs.map(function (id) { return cell(id, line); })));
    });
    rows.push(['', 'Team'].concat(columnIDs.map(function (id) { return cell(id, team); })));
    return csvText(rows);
  }

  function playsCSV(game, playerByID) {
    var rows = [['Period', 'Time', 'Cap', 'Player', 'Event', 'Result', 'Situation', 'Assist', 'Score']];
    var ours = 0, theirs = 0;
    chronological(game).forEach(function (e) {
      if (isGoal(e)) ours++;
      if (e.kind === 'goalAgainst') theirs++;
      var player = playerByID(e.playerID);
      var assist = playerByID(e.assistID);
      var hasSituation = e.kind === 'shot' || e.kind === 'goalAgainst';
      rows.push([
        periodName(e.period), clockText(e.clock), player ? player.capNumber : '', player ? playerName(player) : '',
        KINDS[e.kind], e.outcome ? OUTCOMES[e.outcome] : '', hasSituation ? situationTitle(e.situation, e.kind === 'goalAgainst') : '',
        assist ? playerLabel(assist) : '', ours + '-' + theirs,
      ]);
    });
    return csvText(rows);
  }

  // ---- Sample data, for trying the app without entering anything

  function sampleData() {
    var seed = 2026;
    function rnd(n) { // small deterministic generator
      seed = (seed * 1664525 + 1013904223) % 4294967296;
      return Math.floor((seed / 4294967296) * n);
    }
    function pick(list) { return list[rnd(list.length)]; }
    var names = [['Sam', 'Okafor'], ['Alex', 'Reyes'], ['Jordan', 'Lindqvist'], ['Riley', 'Tanaka'], ['Casey', 'Moreau'], ['Morgan', 'Bianchi'],
      ['Taylor', 'Novak'], ['Quinn', 'Haddad'], ['Avery', 'Costa'], ['Rowan', 'Petrov'], ['Skyler', 'Mbeki'], ['Reese', 'Oduya'], ['Drew', 'Varga']];
    var positions = ['goalkeeper', 'driver', 'center', 'wing', 'point', 'centerBack', 'driver', 'wing', 'utility', 'driver', 'center', 'point', 'goalkeeper'];
    var players = names.map(function (name, i) {
      return { id: uid(), firstName: name[0], lastName: name[1], capNumber: i + 1, position: positions[i], heightCm: 172 + (i * 7) % 22, weightKg: 64 + (i * 5) % 24, isArchived: false };
    });
    var field = players.filter(function (p) { return !isGoalie(p); });
    var goalie = players[0];
    var teams = [{ id: uid(), name: 'Harbor Sharks', playerIDs: players.map(function (p) { return p.id; }) }];

    function makeGame(opponent, daysAgo, lastPeriod, live) {
      var game = newGame({ teamName: 'Harbor Sharks', opponent: opponent, league: 'Fall league', isHome: daysAgo !== 7 });
      game.date = appleNow() - daysAgo * 86400;
      game.rosterIDs = players.map(function (p) { return p.id; });
      game.goalieID = goalie.id;
      for (var period = 1; period <= lastPeriod; period++) {
        var current = live && period === lastPeriod;
        var floor = current ? 300 : 5;
        var clock = game.periodLength;
        var manUp = false, manDown = false;
        var add = function (kind, player, at) {
          var e = { id: uid(), kind: kind, period: period, clock: at, situation: 'even', createdAt: game.date + game.events.length };
          if (player) e.playerID = player.id;
          game.events.push(e);
          return e;
        };
        add(rnd(2) ? 'sprintWon' : 'sprintLost', pick(field), clock);
        for (;;) {
          clock -= 14 + rnd(29);
          if (clock <= floor) break;
          var who = pick(field);
          var roll = rnd(100);
          if (roll < 34) {
            var shot = add('shot', who, clock);
            var r = rnd(100);
            shot.outcome = r < 40 ? 'goal' : r < 70 ? 'saved' : r < 82 ? 'blocked' : 'missed';
            shot.situation = manUp ? 'powerPlay' : 'even';
            shot.location = { x: 0.15 + rnd(700) / 1000, y: 0.12 + rnd(500) / 1000 };
            if (shot.outcome === 'goal' && rnd(100) < 65) {
              shot.assistID = pick(field.filter(function (p) { return p.id !== who.id; })).id;
            }
            manUp = false;
          } else if (roll < 46) add('steal', who, clock);
          else if (roll < 58) add('turnover', who, clock);
          else if (roll < 63) add('block', who, clock);
          else if (roll < 71) { add('exclusionDrawn', who, clock); manUp = true; }
          else if (roll < 78) { add('exclusion', who, clock); manDown = true; }
          else if (roll < 90) { add('save', goalie, clock); manDown = false; }
          else { add('goalAgainst', goalie, clock).situation = manDown ? 'powerPlay' : 'even'; manDown = false; }
        }
        game.period = period;
        game.clock = current ? floor + 12 : 0;
      }
      game.isFinal = !live;
      return game;
    }
    return {
      players: players, teams: teams,
      games: [makeGame('Riverside', 14, 4, false), makeGame('Bay Aquatics', 7, 4, false), makeGame('Northgate', 0, 2, true)],
    };
  }

  WP.model = {
    REGULATION: REGULATION, POSITIONS: POSITIONS, KINDS: KINDS, OUTCOMES: OUTCOMES, SITUATIONS: SITUATIONS,
    COLUMNS: COLUMNS, COLUMN_SETS: COLUMN_SETS,
    appleNow: appleNow, toDate: toDate, fromDate: fromDate, uid: uid,
    position: position, newPlayer: newPlayer, isGoalie: isGoalie, playerName: playerName, shortName: shortName,
    playerLabel: playerLabel, heightText: heightText, weightText: weightText,
    newGame: newGame, periodName: periodName, lengthOf: lengthOf, isRunning: isRunning, remaining: remaining,
    clockSeconds: clockSeconds, startClock: startClock, stopClock: stopClock, adjustClock: adjustClock, resetClock: resetClock,
    goToPeriod: goToPeriod, filtered: filtered, periodsPlayed: periodsPlayed,
    situationTitle: situationTitle, needsPlayer: needsPlayer, isPersonalFoul: isPersonalFoul, isGoal: isGoal, logEvent: logEvent,
    goalsFor: goalsFor, goalsAgainst: goalsAgainst, chronological: chronological,
    emptyLine: emptyLine, personalFouls: personalFouls, shotPct: shotPct, savePct: savePct, playerLines: playerLines,
    teamLine: teamLine, gameLines: gameLines, gameTeamLine: gameTeamLine, seasonLines: seasonLines, seasonTeamLine: seasonTeamLine,
    situationSummary: situationSummary, percent: percent, percent1: percent1, clockText: clockText, columnText: columnText,
    playText: playText, csvText: csvText, statsCSV: statsCSV, playsCSV: playsCSV, sampleData: sampleData,
  };
})();
