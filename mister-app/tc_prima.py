"""Prima Squadra (Prima Categoria – Girone C) letta dagli screenshot Tuttocampo del 23/11/2026."""
import hashlib
import json
import sys
import time

rose_path, out_path = sys.argv[1:3]
TEAM = 'Prima Squadra'
SEASON = '2026/27'


def sid(*parts):
    return 'imp-' + hashlib.sha1('|'.join(parts).encode()).hexdigest()[:16]


rose = json.load(open(rose_path, encoding='utf-8'))['data']
now = int(time.time() * 1000)
team_id = sid('team', TEAM)
season_id = sid('season', TEAM, SEASON)
team = {'id': team_id, 'name': TEAM, 'category': 'Prima Squadra', 'customFields': rose['teams'][0].get('customFields', []), 'updatedAt': now}
season = {'id': season_id, 'teamId': team_id, 'name': SEASON, 'updatedAt': now}

ROSA = {
    'Attaccante': ['Bajrami Denis', 'Cicchi Alex', 'Edoziogor Willis', 'Genovese Giovanni', 'Righetti Alessandro'],
    'Centrocampista': ['Bianchi Jacopo', 'Chiucchiu Edoardo', 'De Santis Josef', 'Lombardi Andrea', 'Ragnacci Pietro', 'Ragusa Gherardo', 'Trecchiodi Pier Luca'],
    'Difensore': ['Apostolico Marco', 'Corbucci Tommaso', 'Coulibaly Nahoua', 'Emidi Mattia', 'Sdringola Emanuele', 'Taddei Ludovico'],
    'Portiere': ['Carrubba Francesco', 'Catana Federico', 'Posi Michele', 'Scattolini Yuri'],
}
# cognome e nome: le prime parole sono il cognome, l'ultima il nome (eccezioni a parte)
SPLIT = {'De Santis Josef': ('De Santis', 'Josef'), 'Trecchiodi Pier Luca': ('Trecchiodi', 'Pier Luca')}
players = []
for role, names in ROSA.items():
    for n in names:
        last, first = SPLIT.get(n, (' '.join(n.split()[:-1]), n.split()[-1]))
        players.append({'id': sid('player', TEAM, n), 'teamId': team_id, 'seasonId': season_id, 'firstName': first, 'lastName': last,
                        'number': '', 'role': role, 'position': '', 'foot': '', 'custom': {}, 'numberHistory': [], 'notes': '', 'updatedAt': now})
pid = {f"{p['lastName']} {p['firstName']}": p['id'] for p in players}

# data, avversario, Palazzo in casa, risultato (gf, gs) o None, ora
G = [
    ('2026-09-05', 'San Luca Calcio', False, (3, 0), ''), ('2026-09-13', 'C4 Foligno', True, (2, 1), ''),
    ('2026-09-20', 'Athletic Club Bastia', False, (4, 1), ''), ('2026-09-27', 'La Castellana 1969', True, (2, 3), ''),
    ('2026-10-04', 'Julia Spello Castello', False, (3, 1), ''), ('2026-10-11', 'Vigor N. Gualdo Bastardo', True, (2, 0), ''),
    ('2026-10-18', 'Real Virtus', False, (2, 0), ''), ('2026-10-25', 'Pontano', True, (3, 1), ''),
    ('2026-11-01', 'Mevania Calcio', False, (2, 0), ''), ('2026-11-08', 'Nocera Umbra 2017', True, (1, 1), ''),
    ('2026-11-15', 'Cascia', False, (1, 0), ''), ('2026-11-22', 'Costano', True, (2, 1), ''),
    ('2026-11-29', 'Grifo Cannara', False, None, '14:30'), ('2026-12-06', 'Superga 48', False, None, '14:30'),
    ('2026-12-13', 'Vis Foligno', True, None, '14:30'),
    # ritorno
    ('2026-12-20', 'San Luca Calcio', True, None, '14:30'), ('2027-01-10', 'C4 Foligno', False, None, '14:30'),
    ('2027-01-17', 'Athletic Club Bastia', True, None, '14:30'), ('2027-01-24', 'La Castellana 1969', False, None, '14:30'),
    ('2027-01-31', 'Julia Spello Castello', True, None, '14:30'), ('2027-02-07', 'Vigor N. Gualdo Bastardo', False, None, '14:30'),
    ('2027-02-14', 'Real Virtus', True, None, '14:30'), ('2027-02-21', 'Pontano', False, None, '14:30'),
    ('2027-02-28', 'Mevania Calcio', True, None, '14:30'), ('2027-03-07', 'Nocera Umbra 2017', False, None, '14:30'),
    ('2027-03-14', 'Cascia', True, None, '14:30'), ('2027-04-04', 'Costano', False, None, '15:30'),
    ('2027-04-11', 'Grifo Cannara', True, None, '15:30'), ('2027-04-18', 'Superga 48', True, None, '15:30'),
    ('2027-04-25', 'Vis Foligno', False, None, '15:30'),
]
matches, events = [], []
for i, (date, opp, home, res, tm) in enumerate(G):
    g, leg = (i + 1, 'andata') if i < 15 else (i - 14, 'ritorno')
    mid = sid('match', TEAM, SEASON, str(g), leg)
    matches.append({
        'id': mid, 'teamId': team_id, 'seasonId': season_id, 'date': date, 'time': tm,
        'opponent': opp, 'home': home, 'competition': 'Campionato', 'round': f'{g}ª giornata {leg}',
        'periodsCount': 2, 'periodMinutes': 45, 'squad': [], 'periods': [],
        'status': 'finita' if res else 'da giocare', 'source': 'tuttocampo', 'place': '', 'notes': '', 'updatedAt': now,
    })
    if res:
        gf, gs = res
        events += [{'id': sid('tc-gol', mid, str(k)), 'matchId': mid, 'period': 1, 't': 0, 'type': 'gol', 'playerId': None, 'result': None, 'source': 'tuttocampo'} for k in range(gf)]
        events += [{'id': sid('tc-golsub', mid, str(k)), 'matchId': mid, 'period': 1, 't': 0, 'type': 'golSubito', 'playerId': None, 'result': None, 'source': 'tuttocampo'} for k in range(gs)]

GOALS = {'Bajrami Denis': 6, 'Cicchi Alex': 6, 'Genovese Giovanni': 5, 'Sdringola Emanuele': 2, 'Bianchi Jacopo': 1, 'Casale Cristian': 1,
         'Chiucchiu Edoardo': 1, 'Coulibaly Nahoua': 1, 'Emidi Mattia': 1, 'Lombardi Andrea': 1, 'Righetti Alessandro': 1}
scorers = [{'name': n, 'playerId': pid.get(n), 'gol': g, 'rigori': 0, 'assist': 0} for n, g in GOALS.items()]
STANDINGS = [
    (1, 'Calcio Palazzo', 31, 12, 10, 1, 1, 27, 9, 18, 'promozione'),
    (2, 'Julia Spello Castello', 27, 12, 8, 3, 1, None, None, 20, 'playoff'),
    (3, 'La Castellana 1969', 26, 12, 8, 2, 2, None, None, 13, 'playoff'),
    (4, 'Pontano', 24, 12, 7, 3, 2, None, None, 8, 'playoff'),
    (5, 'Real Virtus', 23, 12, 7, 2, 3, None, None, 11, 'playoff'),
    (6, 'Costano', 23, 12, 7, 2, 3, None, None, 10, None),
    (7, 'Vis Foligno', 21, 12, 6, 3, 3, None, None, 2, None),
    (8, 'Vigor N. Gualdo Bastardo', 19, 12, 6, 1, 5, None, None, 3, None),
    (9, 'San Luca Calcio', 17, 12, 5, 2, 5, None, None, -2, None),
    (10, 'Superga 48', 13, 12, 2, 7, 3, None, None, -1, None),
    (11, 'Nocera Umbra 2017', 10, 12, 2, 4, 6, None, None, 3, None),
    (12, 'Mevania Calcio', 10, 12, 3, 1, 8, None, None, -10, 'playout'),
    (13, 'Athletic Club Bastia', 8, 12, 2, 2, 8, None, None, -12, 'playout'),
    (14, 'C4 Foligno', 7, 12, 2, 1, 9, None, None, -10, 'playout'),
    (15, 'Cascia', 7, 12, 2, 1, 9, None, None, -19, 'playout'),
    (16, 'Grifo Cannara', 4, 12, 1, 1, 10, None, None, -34, 'retrocessione'),
]
team['tcStats'] = {
    'fonte': 'Tuttocampo', 'aggiornato': '2026-11-23', 'campionato': 'Prima Categoria – Girone C',
    'classifica': [{**dict(zip(['pos', 'squadra', 'pt', 'g', 'v', 'n', 'p', 'gf', 'gs', 'dr'], r[:10])), **({'zona': r[10]} if r[10] else {})} for r in STANDINGS],
    'classificaCompleta': True,
    'legenda': {'promozione': 'Promozione', 'playoff': 'Playoff', 'playout': 'Playout', 'retrocessione': 'Seconda Categoria'},
    'marcatori': scorers,
    'evidenza': ['Capolista del campionato', 'Imbattuta da 8 partite', 'In gol da 12 partite consecutive',
                 'Vittoria più larga: 3-0 contro San Luca Calcio (1ª giornata)', '5 vittorie consecutive (record)',
                 'Capocannoniere della squadra: D. Bajrami (6), A. Cicchi (6)'],
}
json.dump({'app': 'mister-app', 'kind': 'rose', 'version': 1,
           'data': {'teams': [team], 'seasons': [season], 'players': players, 'matches': matches, 'events': events}},
          open(out_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('giocatori', len(players), 'partite', len(matches), 'eventi', len(events), 'non in rosa:', [s['name'] for s in scorers if not s['playerId']])
