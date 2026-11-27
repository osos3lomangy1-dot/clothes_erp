# -*- coding: utf-8 -*-
import json

with open('assets/assistant_knowledge_ar.json', encoding='utf-8') as f:
    kb = json.load(f)

synonyms = kb.get('synonyms', [])
syn_map = {}
for i, group in enumerate(synonyms):
    for word in group:
        syn_map[word] = i

stop_words = {'في', 'من', 'على', 'عن', 'الى', 'مع', 'هذا', 'هذه', 'كل', 'او', 'ان', 'لو', 'ما', 'لا', 'هل'}

def stem(w):
    if len(w) >= 4 and w.startswith('ال'):
        return w[2:]
    return w

def score_topic(topic, query):
    q_tokens = [stem(w) for w in query.split() if w not in stop_words]
    q_groups = {syn_map[w] for w in q_tokens if w in syn_map}
    
    score = 0
    for sq in topic.get('sampleQuestions', []):
        if query == sq: score += 20
        elif query in sq or sq in query: score += 10
        for t in sq.split():
            st = stem(t)
            if st in q_tokens: score += 4.5
            elif st in syn_map and syn_map[st] in q_groups: score += 3.5
            
    for kw in topic.get('keywords', []):
        if kw in query: score += 6
        for t in kw.split():
            st = stem(t)
            if st in q_tokens: score += 4.0
            elif st in syn_map and syn_map[st] in q_groups: score += 3.0
            
    return score

test_queries = [
    'نصاب الزكاة كام النهاردة',
    'ايه هي الزكاة',
    'يعني ايه نقطة التعادل',
    'ايه الفرق بين الربح والايراد',
    'ايه هو الجرد',
    'يعني ايه هامش ربح',
    'ازاي اتعامل مع عميل غاضب',
    'ازاي اتفاوض مع المورد'
]

for q in test_queries:
    scores = [(score_topic(t, q), t['id'], t['title']) for t in kb['topics']]
    scores.sort(key=lambda x: x[0], reverse=True)
    best = scores[0]
    print(f'Query: "{q}" -> Best Match: {best[1]} (Score: {best[0]:.1f}) - {best[2]}')
