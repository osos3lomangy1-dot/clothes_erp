# -*- coding: utf-8 -*-
import json

with open('assets/assistant_knowledge_ar.json', encoding='utf-8') as f:
    kb = json.load(f)

syn_map = {}
for i, group in enumerate(kb.get('synonyms', [])):
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

queries = [
    'ازاي ادير محلي وفريقي بنظام EOS',
    'ازاي اعمل انترفيو لبياع او كاشير واعرف انه شاطر وامين',
    'ازاي اخلي محلي له قيمة وسعر عالي عند التقييم او البيع',
    'ازاي اهرب من حرق الاسعار والمنافسين اللي حواليا',
    'ازاي استخدم تاثير الطعم Decoy Effect في تسعير البضاعة',
    'ازاي اخلي خدمة العملاء هي اللي تجيبلي زباين جديدة',
    'ايه هي اسباب البركة في تجارة المحل',
    'اهم قواعد الادخار وبناء الثروة للتاجر'
]

for q in queries:
    scores = [(score_topic(t, q), t['id'], t['title']) for t in kb['topics']]
    scores.sort(key=lambda x: x[0], reverse=True)
    print(f'Query: "{q}" -> Match: {scores[0][1]} ({scores[0][0]:.1f}) : {scores[0][2]}')
