"""Read human ratings; missing judgments never count as passes."""
import csv
from pathlib import Path
root = Path(__file__).parent
rows = list(csv.DictReader((root / 'human-ratings.csv').open()))
complete = [r for r in rows if r['candidate_id'] and r['rater'] and r['fits_brief'] in ('yes', 'no')]
coverage = {(r['brief_id'], int(r['rank'])) for r in complete}
expected = {(f'B{i:02}', rank) for i in range(1, 31) for rank in range(1, 11)}
if coverage != expected:
    print(f'PENDING: {len(coverage & expected)}/300 brief-position judgments available.')
else:
    accuracy = sum(r['fits_brief'] == 'yes' for r in complete) / len(complete)
    print(f'Human brief fit: {accuracy:.1%}; quality gate: {"PASS" if accuracy >= .9 else "FAIL"}')
blind = list(csv.DictReader((root / 'blind-preference.csv').open()))
choices = [r for r in blind if r['participant'] and r['preferred_version'] in ('v2','baseline','tie')]
participants = {r['participant'] for r in choices}
if len(participants) < 3:
    print('PENDING: blind comparison requires at least three independent participants.')
else:
    wins = sum(sum(r['preferred_version']=='v2' for r in choices if r['participant']==p) > sum(r['preferred_version']=='baseline' for r in choices if r['participant']==p) for p in participants)
    print(f'Participants favoring v2: {wins}/{len(participants)}; preference gate: {"PASS" if wins > len(participants)/2 else "FAIL"}')
