import fs from 'node:fs'
import crypto from 'node:crypto'
import { google } from 'googleapis'
import { Client, Query, TablesDB } from 'node-appwrite'

const DATABASE_ID = process.env.XAPZAP_DATABASE_ID || 'xapzap_db'
const AD_UNIT_REVENUE_TABLE_ID =
  process.env.XAPZAP_AD_UNIT_REVENUE_DAILY_TABLE_ID || 'ad_unit_revenue_daily'
const AD_IMPRESSIONS_TABLE_ID =
  process.env.XAPZAP_AD_IMPRESSIONS_TABLE_ID || 'ad_impressions'
const CREATOR_EARNINGS_TABLE_ID =
  process.env.XAPZAP_CREATOR_EARNINGS_DAILY_TABLE_ID || 'creator_earnings_daily'
const CREATOR_BALANCES_TABLE_ID =
  process.env.XAPZAP_CREATOR_BALANCES_TABLE_ID || 'creator_balances'
const CREATOR_PAYOUTS_TABLE_ID =
  process.env.XAPZAP_CREATOR_PAYOUTS_TABLE_ID || 'creator_payouts'
const REFERRALS_TABLE_ID =
  process.env.XAPZAP_REFERRALS_TABLE_ID || 'referrals'

const DEFAULT_CREATOR_SHARE = 0.45
const DEFAULT_REFERRAL_SHARE = 0.05
const MINIMUM_PAYOUT_USD = 50
const MONTHLY_PAYOUT_DAY = 27

export async function syncAdmobRevenue(payload = {}) {
  const { startDate, endDate } = resolveDateRange(payload)
  const publisherId = readString(payload.publisherId) || resolvePublisherId()
  if (!publisherId) {
    throw new Error(
      'Missing AdMob publisher ID. Set ADMOB_PUBLISHER_ID or pass publisherId.',
    )
  }

  const adUnitConfig = loadAdUnitConfig()
  const { rows, currencyCode } = await fetchAdmobReportRows({
    publisherId,
    startDate,
    endDate,
  })

  const tables = buildAdminTables()
  const revenueRows = await upsertAdUnitRevenue({
    tables,
    rows,
    currencyCode,
  })

  if (payload.allocate === false) {
    return {
      ok: true,
      startDate,
      endDate,
      adUnits: revenueRows,
      allocations: {
        skipped: true,
        reason: 'Allocation disabled for this run.',
      },
    }
  }

  const allocations = await allocateCreatorEarnings({
    tables,
    adUnitConfig,
    revenueRows,
    startDate,
    endDate,
  })

  return {
    ok: true,
    startDate,
    endDate,
    adUnits: revenueRows,
    allocations,
  }
}

export async function processMonthlyCreatorPayouts(payload = {}) {
  const runDate = parseDateString(payload.runDate) || new Date()
  const payoutDate = new Date(
    Date.UTC(
      runDate.getUTCFullYear(),
      runDate.getUTCMonth(),
      MONTHLY_PAYOUT_DAY,
    ),
  )
  const payoutMonthKey = formatMonthKey(runDate)

  if (runDate.getUTCDate() < MONTHLY_PAYOUT_DAY) {
    return {
      ok: true,
      skipped: true,
      reason: 'Monthly payouts run on or after the 27th of each month.',
      minimumPayoutUsd: MINIMUM_PAYOUT_USD,
      payoutDay: MONTHLY_PAYOUT_DAY,
      payoutMonthKey,
      nextScheduledPayoutDate: payoutDate.toISOString(),
    }
  }

  const tables = buildAdminTables()
  const balances = await listAllRows(tables, CREATOR_BALANCES_TABLE_ID, [
    Query.limit(1000),
  ])
  const processed = []
  const skipped = []

  for (const row of balances) {
    const data = readRowData(row)
    const creatorId = readString(data.creatorId)
    const balanceUsd = roundCurrency(readNumber(data.balanceUsd, 0))
    if (!creatorId || balanceUsd < MINIMUM_PAYOUT_USD) {
      skipped.push({
        creatorId,
        balanceUsd,
        reason: 'Below minimum payout threshold.',
      })
      continue
    }

    const payoutRowId = buildStableRowId('payout', [creatorId, payoutMonthKey])
    const existing = await safeGetRow(tables, CREATOR_PAYOUTS_TABLE_ID, payoutRowId)
    if (existing) {
      skipped.push({
        creatorId,
        balanceUsd,
        reason: 'Already processed for this payout month.',
      })
      continue
    }

    const nowIso = new Date().toISOString()
    const payoutAmount = roundCurrency(balanceUsd)
    await tables.createRow({
      databaseId: DATABASE_ID,
      tableId: CREATOR_PAYOUTS_TABLE_ID,
      rowId: payoutRowId,
      data: {
        creatorId,
        amountUsd: payoutAmount,
        status: 'paid',
        requestedAt: nowIso,
        paidAt: nowIso,
        payoutMethod: 'monthly_auto',
        notes: `Automatic monthly payout for ${payoutMonthKey}. Minimum payout is $${MINIMUM_PAYOUT_USD.toFixed(2)}.`,
      },
    })
    await tables.updateRow({
      databaseId: DATABASE_ID,
      tableId: CREATOR_BALANCES_TABLE_ID,
      rowId: readString(row?.$id),
      data: {
        ...data,
        balanceUsd: 0,
        updatedAt: nowIso,
      },
    })
    processed.push({
      creatorId,
      amountUsd: payoutAmount,
      payoutMonthKey,
    })
  }

  return {
    ok: true,
    minimumPayoutUsd: MINIMUM_PAYOUT_USD,
    payoutDay: MONTHLY_PAYOUT_DAY,
    payoutMonthKey,
    payoutDate: payoutDate.toISOString(),
    processed,
    skipped,
  }
}

export function assertAdmobSyncAuthorized(req, payload = {}) {
  const expectedSecret = readString(process.env.XAPZAP_ADMOB_SYNC_SECRET)
  if (!expectedSecret) {
    return
  }

  const providedSecret =
    readString(payload.syncSecret) || readString(getHeader(req, 'x-sync-secret'))
  if (providedSecret != expectedSecret) {
    throw new Error('Unauthorized AdMob sync request.')
  }
}

async function fetchAdmobReportRows({ publisherId, startDate, endDate }) {
  const auth = await buildGoogleAuth()
  const admob = google.admob({ version: 'v1', auth })
  const parent = publisherId.startsWith('accounts/')
    ? publisherId
    : `accounts/${publisherId}`

  const response = await admob.accounts.networkReport.generate({
    parent,
    requestBody: {
      reportSpec: {
        dateRange: {
          startDate: toAdmobDate(startDate),
          endDate: toAdmobDate(endDate),
        },
        dimensions: ['DATE', 'AD_UNIT', 'AD_FORMAT'],
        metrics: [
          'ESTIMATED_EARNINGS',
          'IMPRESSIONS',
          'CLICKS',
          'MATCHED_REQUESTS',
        ],
      },
    },
  })

  return extractAdmobRows(response?.data)
}

async function upsertAdUnitRevenue({ tables, rows, currencyCode }) {
  const summary = []
  for (const row of rows) {
    if (!row.reportDate || !row.adUnitId) {
      continue
    }

    const rowId = buildStableRowId('adrev', [row.reportDate, row.adUnitId])
    const payload = {
      reportDate: row.reportDate,
      adUnitId: row.adUnitId,
      adUnitName: row.adUnitName,
      adFormat: row.adFormat,
      impressions: row.impressions,
      clicks: row.clicks,
      matchedRequests: row.matchedRequests,
      estimatedEarningsMicros: row.estimatedEarningsMicros,
      estimatedEarningsUsd: row.estimatedEarningsUsd,
      currencyCode: currencyCode || row.currencyCode || 'USD',
    }

    await upsertRow(tables, AD_UNIT_REVENUE_TABLE_ID, rowId, payload)
    summary.push(payload)
  }
  return summary
}

async function allocateCreatorEarnings({
  tables,
  adUnitConfig,
  revenueRows,
  startDate,
  endDate,
}) {
  const eligibleRevenueRows = revenueRows.filter((row) =>
    isEligibleAdUnit(adUnitConfig, row.adUnitId),
  )
  if (eligibleRevenueRows.length == 0) {
    return {
      skipped: true,
      reason: 'No eligible ad units matched the configured creator-earning map.',
    }
  }

  const creatorShareRate = readNumber(
    process.env.XAPZAP_CREATOR_SHARE_RATE,
    DEFAULT_CREATOR_SHARE,
  )
  const referralShareRate = readNumber(
    process.env.XAPZAP_REFERRAL_SHARE_RATE,
    DEFAULT_REFERRAL_SHARE,
  )

  const balanceDeltas = new Map()
  const allocationRows = []

  for (const revenueRow of eligibleRevenueRows) {
    const placement = resolvePlacement(adUnitConfig, revenueRow.adUnitId)
    const attributionRows = await listAdImpressions({
      tables,
      adUnitId: revenueRow.adUnitId,
      startDate,
      endDate,
    })

    const totalImpressions = attributionRows.reduce(
      (sum, row) => sum + row.impressions,
      0,
    )
    if (totalImpressions <= 0) {
      continue
    }

    for (const attribution of attributionRows) {
      const revenueRatio = attribution.impressions / totalImpressions
      const creatorGrossUsd =
        revenueRow.estimatedEarningsUsd * revenueRatio * creatorShareRate

      const referralUserId = await resolveReferralUserId(
        tables,
        attribution.creatorId,
      )
      const referralUsd =
        referralUserId == null
          ? 0
          : revenueRow.estimatedEarningsUsd * revenueRatio * referralShareRate
      const creatorNetUsd = Math.max(creatorGrossUsd - referralUsd, 0)

      const allocationPayload = {
        reportDate: attribution.reportDate,
        creatorId: attribution.creatorId,
        adUnitId: revenueRow.adUnitId,
        placement,
        impressions: attribution.impressions,
        totalImpressions,
        adUnitRevenueUsd: revenueRow.estimatedEarningsUsd,
        creatorShareRate,
        referralShareRate: referralUserId == null ? 0 : referralShareRate,
        creatorEarningsUsd: roundCurrency(creatorNetUsd),
        referralEarningsUsd: roundCurrency(referralUsd),
        referralUserId: referralUserId || '',
      }

      const rowId = buildStableRowId('earn', [
        attribution.reportDate,
        attribution.creatorId,
        revenueRow.adUnitId,
        placement,
      ])
      await upsertRow(tables, CREATOR_EARNINGS_TABLE_ID, rowId, allocationPayload)
      allocationRows.push(allocationPayload)

      addBalanceDelta(
        balanceDeltas,
        attribution.creatorId,
        allocationPayload.creatorEarningsUsd,
      )
      if (referralUserId != null && allocationPayload.referralEarningsUsd > 0) {
        addBalanceDelta(
          balanceDeltas,
          referralUserId,
          allocationPayload.referralEarningsUsd,
        )
      }
    }
  }

  for (const [creatorId, delta] of balanceDeltas.entries()) {
    await applyBalanceDelta(tables, creatorId, delta)
  }

  return {
    count: allocationRows.length,
    rows: allocationRows,
  }
}

async function listAdImpressions({ tables, adUnitId, startDate, endDate }) {
  const dateField = process.env.XAPZAP_AD_IMPRESSIONS_DATE_FIELD || 'eventDate'
  const aggregated = new Map()

  for (const reportDate of enumerateDates(startDate, endDate)) {
    const rows = await listAllRows(tables, AD_IMPRESSIONS_TABLE_ID, [
      Query.equal('adUnitId', adUnitId),
      Query.equal(dateField, reportDate),
    ])

    for (const row of rows) {
      const data = readRowData(row)
      const creatorId = readString(data.creatorId)
      if (!creatorId) {
        continue
      }

      const key = `${reportDate}|${creatorId}`
      const current = aggregated.get(key) || 0
      aggregated.set(key, current + readNumber(data.impressions, 1))
    }
  }

  return [...aggregated.entries()].map(([key, impressions]) => {
    const [reportDate, creatorId] = key.split('|')
    return { reportDate, creatorId, impressions }
  })
}

async function applyBalanceDelta(tables, creatorId, deltaUsd) {
  if (!creatorId || deltaUsd <= 0) {
    return
  }

  const existingRows = await listAllRows(tables, CREATOR_BALANCES_TABLE_ID, [
    Query.equal('creatorId', creatorId),
    Query.limit(1),
  ])

  if (existingRows.isEmpty) {
    await tables.createRow({
      databaseId: DATABASE_ID,
      tableId: CREATOR_BALANCES_TABLE_ID,
      rowId: buildStableRowId('bal', [creatorId]),
      data: {
        creatorId,
        balanceUsd: roundCurrency(deltaUsd),
        updatedAt: new Date().toISOString(),
      },
    })
    return
  }

  const row = existingRows.first
  const data = readRowData(row)
  const currentBalance = readNumber(data.balanceUsd, 0)
  await tables.updateRow({
    databaseId: DATABASE_ID,
    tableId: CREATOR_BALANCES_TABLE_ID,
    rowId: row.$id,
    data: {
      ...data,
      balanceUsd: roundCurrency(currentBalance + deltaUsd),
      updatedAt: new Date().toISOString(),
    },
  })
}

async function resolveReferralUserId(tables, creatorId) {
  const rows = await listAllRows(tables, REFERRALS_TABLE_ID, [
    Query.equal('referredUserId', creatorId),
    Query.limit(1),
  ])
  if (rows.isEmpty) {
    return null
  }

  const data = readRowData(rows.first)
  return (
    readString(data.referrerUserId) ||
    readString(data.referrerId) ||
    readString(data.referrer) ||
    null
  )
}

async function safeGetRow(tables, tableId, rowId) {
  try {
    return await tables.getRow({
      databaseId: DATABASE_ID,
      tableId,
      rowId,
    })
  } catch (err) {
    if (isNotFoundError(err)) {
      return null
    }
    throw err
  }
}

function parseDateString(value) {
  const raw = readString(value)
  if (!raw) {
    return null
  }
  const parsed = new Date(raw)
  return Number.isNaN(parsed.getTime()) ? null : parsed
}

function formatMonthKey(date) {
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}`
}

function loadAdUnitConfig() {
  const envJson = readString(process.env.XAPZAP_ADMOB_AD_UNIT_MAP)
  if (envJson) {
    try {
      return normalizeAdUnitConfig(JSON.parse(envJson))
    } catch (_) {
      // Fall back to CSV envs below.
    }
  }

  return {
    rewardedWatch: readList(process.env.XAPZAP_REWARDED_WATCH_AD_UNITS),
    rewardedReels: readList(process.env.XAPZAP_REWARDED_REELS_AD_UNITS),
    nativeDetail: readList(process.env.XAPZAP_NATIVE_DETAIL_AD_UNITS),
    nativeFeed: readList(process.env.XAPZAP_NATIVE_FEED_AD_UNITS),
  }
}

function normalizeAdUnitConfig(value) {
  const rewarded = value?.rewarded || {}
  const native = value?.native || {}
  return {
    rewardedWatch: readList(rewarded.watch),
    rewardedReels: readList(rewarded.reels),
    nativeDetail: readList(native.detail),
    nativeFeed: readList(native.feed),
  }
}

function resolvePlacement(adUnitConfig, adUnitId) {
  if (adUnitConfig.rewardedWatch.includes(adUnitId)) {
    return 'rewarded_watch'
  }
  if (adUnitConfig.rewardedReels.includes(adUnitId)) {
    return 'rewarded_reels'
  }
  if (adUnitConfig.nativeDetail.includes(adUnitId)) {
    return 'native_detail'
  }
  if (adUnitConfig.nativeFeed.includes(adUnitId)) {
    return 'native_feed'
  }
  return 'unknown'
}

function isEligibleAdUnit(adUnitConfig, adUnitId) {
  return (
    adUnitConfig.rewardedWatch.includes(adUnitId) ||
    adUnitConfig.rewardedReels.includes(adUnitId) ||
    adUnitConfig.nativeDetail.includes(adUnitId)
  )
}

async function buildGoogleAuth() {
  const jsonString =
    readString(process.env.ADMOB_SERVICE_ACCOUNT_JSON) ||
    readStringFromPath(process.env.ADMOB_SERVICE_ACCOUNT_PATH)

  if (!jsonString) {
    throw new Error(
      'Missing AdMob service account JSON. Set ADMOB_SERVICE_ACCOUNT_JSON in the function variables.',
    )
  }

  return new google.auth.GoogleAuth({
    credentials: JSON.parse(jsonString),
    scopes: ['https://www.googleapis.com/auth/admob.readonly'],
  })
}

function resolvePublisherId() {
  return (
    readString(process.env.ADMOB_PUBLISHER_ID) ||
    readString(process.env.ADMOB_ACCOUNT_ID)
  )
}

function readStringFromPath(pathValue) {
  const filePath = readString(pathValue)
  if (!filePath) {
    return null
  }
  try {
    return fs.readFileSync(filePath, 'utf8')
  } catch (_) {
    return null
  }
}

function extractAdmobRows(payload) {
  const rawRows = Array.isArray(payload?.rows) ? payload.rows : []
  const rows = rawRows
    .map((row) => normalizeAdmobRow(row))
    .filter((row) => row != null)

  return {
    rows,
    currencyCode:
      readString(payload?.footer?.matchingRowCount) == null
        ? readString(payload?.footer?.currencyCode)
        : readString(payload?.footer?.currencyCode),
  }
}

function normalizeAdmobRow(row) {
  const dimensions = row?.dimensionValues || {}
  const metrics = row?.metricValues || {}

  const rawDate =
    readString(dimensions?.DATE?.value) ||
    readString(dimensions?.DATE?.displayLabel)
  const adUnitId =
    readString(dimensions?.AD_UNIT?.value) ||
    readString(dimensions?.AD_UNIT_ID?.value)
  if (!rawDate || !adUnitId) {
    return null
  }

  const earningsMicros =
    readNumber(metrics?.ESTIMATED_EARNINGS?.microsValue, 0) ||
    readNumber(metrics?.ESTIMATED_EARNINGS?.integerValue, 0)

  return {
    reportDate: formatDate(rawDate),
    adUnitId,
    adUnitName:
      readString(dimensions?.AD_UNIT?.displayLabel) ||
      readString(dimensions?.AD_UNIT_NAME?.value) ||
      '',
    adFormat:
      readString(dimensions?.AD_FORMAT?.value) ||
      readString(dimensions?.AD_FORMAT?.displayLabel) ||
      '',
    impressions: readNumber(metrics?.IMPRESSIONS?.integerValue, 0),
    clicks: readNumber(metrics?.CLICKS?.integerValue, 0),
    matchedRequests: readNumber(metrics?.MATCHED_REQUESTS?.integerValue, 0),
    estimatedEarningsMicros: earningsMicros,
    estimatedEarningsUsd: roundCurrency(earningsMicros / 1000000),
    currencyCode: readString(metrics?.ESTIMATED_EARNINGS?.currencyCode) || 'USD',
  }
}

function toAdmobDate(dateString) {
  const [year, month, day] = dateString.split('-').map((value) => Number(value))
  return { year, month, day }
}

function resolveDateRange(payload) {
  const date = normalizeDate(readString(payload.date))
  if (date) {
    return { startDate: date, endDate: date }
  }

  const startDate = normalizeDate(readString(payload.startDate))
  const endDate = normalizeDate(readString(payload.endDate))
  if (startDate && endDate) {
    return { startDate, endDate }
  }

  const fallback = new Date(Date.now() - 86400000).toISOString().slice(0, 10)
  return { startDate: fallback, endDate: fallback }
}

function normalizeDate(value) {
  if (!value) {
    return null
  }
  if (/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return value
  }
  if (/^\d{8}$/.test(value)) {
    return `${value.slice(0, 4)}-${value.slice(4, 6)}-${value.slice(6, 8)}`
  }
  return null
}

function formatDate(value) {
  if (/^\d{8}$/.test(value)) {
    return `${value.slice(0, 4)}-${value.slice(4, 6)}-${value.slice(6, 8)}`
  }
  return value.slice(0, 10)
}

function enumerateDates(startDate, endDate) {
  const dates = []
  let current = new Date(`${startDate}T00:00:00Z`)
  const last = new Date(`${endDate}T00:00:00Z`)
  while (current <= last) {
    dates.push(current.toISOString().slice(0, 10))
    current = new Date(current.getTime() + 86400000)
  }
  return dates
}

function buildAdminTables() {
  const endpoint =
    process.env.APPWRITE_FUNCTION_API_ENDPOINT ||
    process.env.APPWRITE_ENDPOINT ||
    ''
  const projectId =
    process.env.APPWRITE_FUNCTION_PROJECT_ID ||
    process.env.APPWRITE_PROJECT_ID ||
    ''
  const apiKey =
    process.env.APPWRITE_FUNCTION_API_KEY || process.env.APPWRITE_API_KEY || ''

  if (!endpoint || !projectId) {
    throw new Error('Missing Appwrite function endpoint or project ID.')
  }
  if (!apiKey) {
    throw new Error(
      'Missing Appwrite Function API key. Set APPWRITE_FUNCTION_API_KEY or APPWRITE_API_KEY in the function environment.',
    )
  }

  const client = new Client().setEndpoint(endpoint).setProject(projectId).setKey(apiKey)
  return new TablesDB(client)
}

async function listAllRows(tables, tableId, queries = []) {
  const rows = []
  let cursorId = null
  let passes = 0

  while (passes < 200) {
    const result = await tables.listRows({
      databaseId: DATABASE_ID,
      tableId,
      queries: [
        ...queries,
        Query.limit(100),
        ...(cursorId ? [Query.cursorAfter(cursorId)] : []),
      ],
    })
    const fetched = Array.isArray(result.rows) ? result.rows : []
    if (fetched.length == 0) {
      break
    }

    rows.push(...fetched)
    cursorId = readString(fetched[fetched.length - 1]?.$id)
    if (!cursorId || fetched.length < 100) {
      break
    }
    passes += 1
  }

  return rows
}

async function upsertRow(tables, tableId, rowId, data) {
  try {
    await tables.updateRow({
      databaseId: DATABASE_ID,
      tableId,
      rowId,
      data,
    })
  } catch (err) {
    if (isNotFoundError(err)) {
      await tables.createRow({
        databaseId: DATABASE_ID,
        tableId,
        rowId,
        data,
      })
      return
    }
    throw err
  }
}

function buildStableRowId(prefix, values) {
  const digest = crypto
    .createHash('sha1')
    .update(values.filter(Boolean).join('|'))
    .digest('hex')
    .slice(0, 30)
  return `${prefix}_${digest}`
}

function addBalanceDelta(map, creatorId, delta) {
  if (!creatorId || !Number.isFinite(delta) || delta <= 0) {
    return
  }
  map.set(creatorId, (map.get(creatorId) || 0) + delta)
}

function roundCurrency(value) {
  if (!Number.isFinite(value)) {
    return 0
  }
  return Math.round(value * 100) / 100
}

function readRowData(row) {
  return row?.data && typeof row.data === 'object'
    ? row.data
    : Object.fromEntries(
        Object.entries(row || {}).filter(([key]) => !key.startsWith('$')),
      )
}

function getHeader(req, name) {
  const lookup = name.toLowerCase()
  for (const [key, value] of Object.entries(req?.headers || {})) {
    if (key.toLowerCase() === lookup) {
      return Array.isArray(value) ? value[0] : value
    }
  }
  return undefined
}

function readString(value) {
  if (value === null || value === undefined) {
    return null
  }
  const normalized = String(value).trim()
  if (!normalized || normalized.toLowerCase() === 'null') {
    return null
  }
  return normalized
}

function readNumber(value, fallback = 0) {
  if (value === null || value === undefined || value === '') {
    return fallback
  }
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : fallback
}

function readList(value) {
  if (!value) {
    return []
  }
  if (Array.isArray(value)) {
    return value.map(readString).filter(Boolean)
  }
  return String(value)
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean)
}

function isNotFoundError(err) {
  const code = Number(err?.code || 0)
  const type = String(err?.type || '').toLowerCase()
  const message = String(err?.message || '').toLowerCase()
  return code === 404 || type.includes('not_found') || message.includes('not found')
}
