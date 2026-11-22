// What a donation campaign for an animal in treatment tells donors, built
// from the rescue case on the server (saveCampaign / setCampaignStatus in
// functions/campaigns.js): the rescue reason, the medical condition, the
// treatment log and the treatment expenses, whose total is the campaign's
// target. Cases, their expenses and treatment logs are staff-only, so this
// public summary is stored on the campaign. No Firebase here, so
// `node --test` checks it.
//
// An expense or log with no `animalIndexes` is shared by every animal on
// the case: each animal's campaign takes an equal share of a shared
// expense (to the centavo, the first animals taking any leftover centavo),
// so a case's costs are never raised twice.

const NOTES_MAX = 300;
const centavos = (pesos) => Math.round(Number(pesos) * 100);

function toMs(v) {
  if (v == null) return null;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  return typeof v === 'number' ? v : null;
}

function text(v, max = 200) {
  if (typeof v !== 'string') return null;
  const s = v.trim();
  return s ? s.slice(0, max) : null;
}

function appliesTo(indexes, index) {
  return !Array.isArray(indexes) || indexes.length === 0 || indexes.includes(index);
}

function animalCountOf(caseData) {
  return Array.isArray(caseData.animals) && caseData.animals.length ? caseData.animals.length : 1;
}

/// Is this animal past intake? An animal record made from it, or its intake
/// marked complete on the case.
function intakeComplete({caseData, animalIndex, records}) {
  if ((records || []).some((r) => r.sourceAnimalIndex === animalIndex)) return true;
  const animals = Array.isArray(caseData.animals) ? caseData.animals : [];
  const a = animals[animalIndex];
  return !!(a && a.intakeCompletedAt) || (animals.length <= 1 && !!caseData.intakeCompletedAt);
}

/// The public summary and the target for one animal of a case.
/// [expenses] and [logs] are raw documents; [records] are animal records
/// made from this case.
function buildAnimalNeeds({caseData, animalIndex, expenses = [], logs = [], records = []}) {
  const count = animalCountOf(caseData);
  const animals = Array.isArray(caseData.animals) ? caseData.animals : [];
  const animal = animals[animalIndex] || (animalIndex === 0 ? caseData : {});

  const items = [];
  for (const e of expenses) {
    const amountC = centavos(e.amount);
    if (!(amountC > 0) || !appliesTo(e.animalIndexes, animalIndex)) continue;
    const shared = !Array.isArray(e.animalIndexes) || e.animalIndexes.length === 0;
    let shareC = amountC;
    if (shared && count > 1) {
      shareC = Math.floor(amountC / count) + (animalIndex < amountC % count ? 1 : 0);
    }
    if (shareC <= 0) continue;
    items.push({
      title: text(e.title, 120) || 'Expense',
      category: text(e.category, 60) || 'Other',
      amount: shareC / 100,
      fullAmount: amountC / 100,
      shared: shared && count > 1,
      dateMs: toMs(e.incurredAt) || toMs(e.createdAt),
    });
  }
  items.sort((a, b) => (a.dateMs || 0) - (b.dateMs || 0));
  const totalC = items.reduce((s, it) => s + centavos(it.amount), 0);

  const log = [];
  for (const l of logs) {
    if (!appliesTo(l.animalIndexes, animalIndex)) continue;
    log.push({
      dateMs: toMs(l.treatmentDate) || toMs(l.timestamp),
      type: text(l.type, 60) || 'Update',
      condition: text(l.finalCondition, 120) || text(l.condition, 120),
      procedure: text(l.procedurePerformed, 120),
      medication: text(l.medicationName, 120),
      vaccine: text(l.vaccineName, 120),
      notes: text(l.notes, NOTES_MAX),
    });
  }
  log.sort((a, b) => (a.dateMs || 0) - (b.dateMs || 0));
  const latest = [...log].reverse().find((l) => l.condition);

  return {
    expenseTotal: totalC / 100,
    animalNeeds: {
      caseId: null, // set by the caller
      animalIndex,
      animalName: text(animal.name, 80),
      species: text(animal.species, 40) || text(caseData.species, 40),
      rescueType: text(caseData.rescueType, 80),
      reportedCondition: text(animal.condition, 1000) || text(caseData.condition, 1000),
      currentCondition: latest ? latest.condition : null,
      treatmentLog: log,
      expenses: items,
      expenseTotal: totalC / 100,
      intakeComplete: intakeComplete({caseData, animalIndex, records}),
    },
  };
}

module.exports = {buildAnimalNeeds, intakeComplete, appliesTo};
