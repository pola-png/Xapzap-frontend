import { google } from 'googleapis'
import { Account, Client, Query, Storage, TablesDB, Users } from 'node-appwrite'
import {
  assertAdmobSyncAuthorized,
  processMonthlyCreatorPayouts,
  syncAdmobRevenue,
} from './admob_sync.js'

const DATABASE_ID = process.env.XAPZAP_DATABASE_ID || 'xapzap_db'
const POSTS_TABLE_ID = process.env.XAPZAP_POSTS_TABLE_ID || 'posts'
const COMMENTS_TABLE_ID = process.env.XAPZAP_COMMENTS_TABLE_ID || 'comments'
const PROFILES_TABLE_ID = process.env.XAPZAP_PROFILES_TABLE_ID || 'profiles'
const FOLLOWS_TABLE_ID = process.env.XAPZAP_FOLLOWS_TABLE_ID || 'follows'
const LIKES_TABLE_ID = process.env.XAPZAP_LIKES_TABLE_ID || 'likes'
const COMMENT_LIKES_TABLE_ID =
  process.env.XAPZAP_COMMENT_LIKES_TABLE_ID || 'comment_likes'
const REPOSTS_TABLE_ID = process.env.XAPZAP_REPOSTS_TABLE_ID || 'reposts'
const REPORTS_TABLE_ID = process.env.XAPZAP_REPORTS_TABLE_ID || 'reports'
const SAVES_TABLE_ID = process.env.XAPZAP_SAVES_TABLE_ID || 'saves'
const BLOCKS_TABLE_ID = process.env.XAPZAP_BLOCKS_TABLE_ID || 'blocks'
const REFERRALS_TABLE_ID = process.env.XAPZAP_REFERRALS_TABLE_ID || 'referrals'
const NOTIFICATIONS_TABLE_ID =
  process.env.XAPZAP_NOTIFICATIONS_TABLE_ID || 'notifications'
const POST_AGGREGATES_TABLE_ID =
  process.env.XAPZAP_POST_AGGREGATES_TABLE_ID || 'post_aggregates'
const FEED_EVENTS_TABLE_ID = process.env.XAPZAP_FEED_EVENTS_TABLE_ID || 'feed_events'

export default async ({ req, res, error }) => {
  try {
    if (isNotificationCreateEvent(req)) {
      return res.json(await dispatchNotificationFromEvent(req))
    }

    const path = normalizePath(req.path)
    const payload = parseJsonBody(req)

    switch (path) {
      case '/v1/notifications/dispatch':
        return res.json(await dispatchNotificationPayload(payload))
      case '/v1/admob/sync':
      case '/v1/admin/admob/sync':
        assertAdmobSyncAuthorized(req, payload)
        return res.json(await syncAdmobRevenue(payload))
      case '/v1/admin/admob/payouts/process':
        assertAdmobSyncAuthorized(req, payload)
        return res.json(await processMonthlyCreatorPayouts(payload))
      case '/v1/account/delete':
        return res.json(await deleteCurrentAccount(req, payload))
      case '/v1/feed/home':
        return res.json(await withScopedFiltering(req, (tables, blockedIds) =>
          fetchHomeFeed(tables, blockedIds, payload),
        ))
      case '/v1/feed/user-posts':
        return res.json(await withScopedFiltering(req, (tables, blockedIds) =>
          fetchUserPosts(tables, blockedIds, payload),
        ))
      case '/v1/feed/post':
        {
          const scopedTables = buildScopedTables(req)
          const scopedUserId = getHeader(req, 'x-appwrite-user-id')
          const blockedIds = await loadBlockedIds(scopedTables, scopedUserId)
          const row = await fetchPost(scopedTables, blockedIds, payload)
          if (!row) {
            return res.json(
              {
                error: 'Post not found.',
                code: 'post_not_found',
              },
              404,
            )
          }
          return res.json(row)
        }
      case '/v1/feed/hashtag':
        return res.json(await withScopedFiltering(req, (tables, blockedIds) =>
          fetchHashtagFeed(tables, blockedIds, payload),
        ))
      case '/v1/feed/comments':
        return res.json(await withScopedFiltering(req, (tables, blockedIds) =>
          fetchComments(tables, blockedIds, payload),
        ))
      case '/v1/feed/saved-posts':
        return res.json(
          await withScopedFiltering(req, (tables, blockedIds, scopedUserId) =>
            fetchSavedPosts(tables, blockedIds, payload, scopedUserId),
          ),
        )
      default:
        return res.json(
          {
            error: 'Unknown block-filter route.',
            route: path,
          },
          404,
        )
    }
  } catch (err) {
    error?.(String(err?.stack || err))
    return res.json(
      {
        error: err instanceof Error ? err.message : 'Block filter failed.',
      },
      500,
    )
  }
}

function isNotificationCreateEvent(req) {
  const trigger = readString(getHeader(req, 'x-appwrite-trigger'))
  const event = readString(getHeader(req, 'x-appwrite-event'))
  if (trigger !== 'event' || !event) {
    return false
  }
  const normalized = event.toLowerCase()
  return (
    normalized.includes('.rows.') &&
    normalized.endsWith('.create') &&
    normalized.includes(`.${NOTIFICATIONS_TABLE_ID.toLowerCase()}.`)
  )
}

async function dispatchNotificationFromEvent(req) {
  const payload = parseJsonBody(req)
  const row = payload?.$id ? payload : payload?.data?.$id ? payload.data : payload
  return dispatchNotificationPayload({
    notification: row,
  })
}

async function dispatchNotificationPayload(payload = {}) {
  const notification = normalizeNotificationPayload(payload)
  const userId = readString(notification.userId)
  if (!userId) {
    throw new Error('Notification userId is required.')
  }

  const { tables } = buildAdminServices()
  const profile = await getProfileByUserIdAdmin(tables, userId)
  if (!profile) {
    return {
      ok: false,
      skipped: true,
      reason: 'profile_not_found',
      userId,
    }
  }

  const profileData = readRowData(profile)
  const pushEnabled = readBoolean(profileData.pushNotificationsEnabled, true)
  const fcmToken = readString(profileData.fcmToken)

  if (!pushEnabled) {
    return {
      ok: false,
      skipped: true,
      reason: 'push_disabled',
      userId,
    }
  }

  if (!fcmToken) {
    return {
      ok: false,
      skipped: true,
      reason: 'missing_fcm_token',
      userId,
    }
  }

  const title = readString(notification.title) || 'XapZap'
  const body = readString(notification.body) || ''
  const actorAvatar =
    readString(notification.actorAvatar) || readString(notification.avatarUrl) || ''
  const notificationId = readString(notification.$id) || readString(notification.id) || ''
  const type = readString(notification.type) || 'generic'
  const actionUrl =
    readString(notification.actionUrl) ||
    readString(notification.deepLink) ||
    readString(notification.url) ||
    ''

  try {
    const response = await sendFcmMessage({
      token: fcmToken,
      title,
      body,
      data: {
        notificationId,
        type,
        userId,
        actorAvatar,
        actionUrl,
      },
    })

    return {
      ok: true,
      delivered: true,
      userId,
      notificationId,
      fcm: response,
    }
  } catch (err) {
    if (isInvalidFcmTokenError(err)) {
      await clearStoredFcmToken(tables, profile)
      return {
        ok: false,
        delivered: false,
        clearedToken: true,
        reason: 'invalid_fcm_token',
        userId,
        notificationId,
      }
    }
    throw err
  }
}

function normalizeNotificationPayload(payload) {
  if (payload?.notification && typeof payload.notification === 'object') {
    return payload.notification
  }
  if (payload?.row && typeof payload.row === 'object') {
    return payload.row
  }
  return payload && typeof payload === 'object' ? payload : {}
}

async function getProfileByUserIdAdmin(tables, userId) {
  const result = await safeListRows(tables, PROFILES_TABLE_ID, [
    Query.equal('userId', userId),
    Query.limit(1),
  ])
  return result.rows?.[0] || null
}

async function clearStoredFcmToken(tables, profile) {
  const rowId = readString(profile?.$id)
  const data = readRowData(profile)
  const userId = readString(data.userId) || rowId
  if (!rowId || !userId) {
    return
  }
  try {
    await tables.updateRow({
      databaseId: DATABASE_ID,
      tableId: PROFILES_TABLE_ID,
      rowId,
      data: {
        userId,
        fcmToken: '',
        pushUpdatedAt: new Date().toISOString(),
      },
    })
  } catch (_) {
    // Ignore schema/update mismatches so notification delivery failures
    // do not break the main function flow.
  }
}

async function sendFcmMessage({ token, title, body, data = {} }) {
  const projectId =
    readString(process.env.FIREBASE_PROJECT_ID) ||
    readString(process.env.GOOGLE_CLOUD_PROJECT) ||
    readString(process.env.GCLOUD_PROJECT)
  const clientEmail = readString(process.env.FIREBASE_CLIENT_EMAIL)
  const privateKeyRaw = readString(process.env.FIREBASE_PRIVATE_KEY)

  if (!projectId || !clientEmail || !privateKeyRaw) {
    throw new Error(
      'Missing Firebase server credentials. Set FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, and FIREBASE_PRIVATE_KEY in the function environment.',
    )
  }

  const privateKey = privateKeyRaw.replace(/\\n/g, '\n')
  const auth = new google.auth.JWT({
    email: clientEmail,
    key: privateKey,
    scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
  })

  const { access_token: accessToken } = await auth.authorize()
  if (!accessToken) {
    throw new Error('Failed to authorize Firebase messaging request.')
  }

  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token,
          notification: {
            title,
            body,
          },
          data: Object.fromEntries(
            Object.entries(data)
              .map(([key, value]) => [key, value == null ? '' : String(value)])
              .filter(([, value]) => value !== ''),
          ),
          android: {
            priority: 'high',
            notification: {
              channel_id: 'xapzap_notifications',
              default_sound: true,
            },
          },
        },
      }),
    },
  )

  const json = await response.json().catch(() => ({}))
  if (!response.ok) {
    const error = new Error(
      `FCM send failed with ${response.status}: ${JSON.stringify(json)}`,
    )
    error.details = json
    throw error
  }

  return json
}

function isInvalidFcmTokenError(err) {
  const raw =
    JSON.stringify(err?.details || {}) +
    ' ' +
    String(err?.message || '')
  const normalized = raw.toLowerCase()
  return (
    normalized.includes('unregistered') ||
    normalized.includes('invalid registration token') ||
    normalized.includes('registration-token-not-registered')
  )
}

async function withScopedFiltering(req, handler) {
  const scopedTables = buildScopedTables(req)
  const scopedUserId = getHeader(req, 'x-appwrite-user-id')
  const blockedIds = await loadBlockedIds(scopedTables, scopedUserId)
  return handler(scopedTables, blockedIds, scopedUserId)
}

function normalizePath(value) {
  const raw = typeof value === 'string' ? value.trim() : ''
  if (!raw) {
    return '/'
  }
  return raw.startsWith('/') ? raw : `/${raw}`
}

function parseJsonBody(req) {
  if (req.bodyJson && typeof req.bodyJson === 'object') {
    return req.bodyJson
  }

  const rawBody =
    typeof req.bodyText === 'string'
      ? req.bodyText
      : typeof req.body === 'string'
        ? req.body
        : ''
  if (!rawBody.trim()) {
    return {}
  }

  return JSON.parse(rawBody)
}

function getHeader(req, name) {
  const headers = req.headers || {}
  const lookup = name.toLowerCase()
  for (const [key, value] of Object.entries(headers)) {
    if (key.toLowerCase() === lookup) {
      return Array.isArray(value) ? value[0] : value
    }
  }
  return undefined
}

function resolveAppwriteConfig() {
  return {
    endpoint:
      process.env.APPWRITE_FUNCTION_API_ENDPOINT ||
      process.env.APPWRITE_ENDPOINT ||
      '',
    projectId:
      process.env.APPWRITE_FUNCTION_PROJECT_ID ||
      process.env.APPWRITE_PROJECT_ID ||
      '',
  }
}

function buildScopedTables(req) {
  const { endpoint, projectId } = resolveAppwriteConfig()

  if (!endpoint || !projectId) {
    throw new Error('Missing Appwrite function endpoint or project ID.')
  }

  const client = new Client().setEndpoint(endpoint).setProject(projectId)
  const userJwt = getHeader(req, 'x-appwrite-user-jwt')
  const dynamicKey =
    getHeader(req, 'x-appwrite-key') ||
    process.env.APPWRITE_FUNCTION_API_KEY ||
    process.env.APPWRITE_API_KEY

  if (userJwt) {
    client.setJWT(userJwt)
  } else if (dynamicKey) {
    client.setKey(dynamicKey)
  } else {
    throw new Error('Missing Appwrite function credentials.')
  }

  return new TablesDB(client)
}

function buildAdminServices() {
  const { endpoint, projectId } = resolveAppwriteConfig()
  const apiKey =
    process.env.APPWRITE_FUNCTION_API_KEY ||
    process.env.APPWRITE_API_KEY ||
    ''

  if (!endpoint || !projectId) {
    throw new Error('Missing Appwrite function endpoint or project ID.')
  }
  if (!apiKey) {
    throw new Error(
      'Missing Appwrite Function API key. Set APPWRITE_FUNCTION_API_KEY or APPWRITE_API_KEY in the function environment.',
    )
  }

  const client = new Client().setEndpoint(endpoint).setProject(projectId).setKey(apiKey)
  return {
    tables: new TablesDB(client),
    users: new Users(client),
    storage: new Storage(client),
  }
}

async function resolveAuthenticatedUserId(req, payload = {}) {
  const headerUserId = readString(getHeader(req, 'x-appwrite-user-id'))
  const userJwt =
    readString(payload.userJwt) || readString(getHeader(req, 'x-appwrite-user-jwt'))

  if (!userJwt) {
    throw new Error('Authentication required.')
  }

  const { endpoint, projectId } = resolveAppwriteConfig()
  if (!endpoint || !projectId) {
    throw new Error('Missing Appwrite function endpoint or project ID.')
  }

  const client = new Client().setEndpoint(endpoint).setProject(projectId).setJWT(userJwt)
  const account = new Account(client)
  const user = await account.get()
  const resolvedUserId = readString(user?.$id)

  if (!resolvedUserId) {
    throw new Error('Authenticated user could not be resolved.')
  }
  if (headerUserId && headerUserId !== resolvedUserId) {
    throw new Error('Authenticated user mismatch.')
  }

  return resolvedUserId
}

async function deleteCurrentAccount(req, payload) {
  if (payload?.confirm !== true) {
    throw new Error('Deletion confirmation required.')
  }

  const userId = await resolveAuthenticatedUserId(req, payload)
  const { tables, users, storage } = buildAdminServices()

  const profileRows = await listAllRows(tables, PROFILES_TABLE_ID, [
    Query.equal('userId', userId),
  ])
  const ownedPosts = await listAllRows(tables, POSTS_TABLE_ID, [
    Query.equal('userId', userId),
  ])
  const ownedPostIds = ownedPosts
    .map((row) => readString(row?.$id))
    .filter(Boolean)

  const ownComments = await listAllRows(tables, COMMENTS_TABLE_ID, [
    Query.equal('userId', userId),
  ])
  const commentsOnOwnedPosts = await listRowsByFieldValues(
    tables,
    COMMENTS_TABLE_ID,
    'postId',
    ownedPostIds,
  )
  const rootCommentIds = uniqueStrings([
    ...ownComments.map((row) => readString(row?.$id)),
    ...commentsOnOwnedPosts.map((row) => readString(row?.$id)),
  ])
  const commentIds = await collectCommentTreeIds(tables, rootCommentIds)

  const appwriteFileRefs = extractAppwriteFileRefs([
    ...profileRows.flatMap((row) => [
      readRowData(row).avatarUrl,
      readRowData(row).coverUrl,
    ]),
    ...ownedPosts.flatMap((row) => {
      const data = readRowData(row)
      return [
        data.userAvatar,
        ...(Array.isArray(data.mediaUrls) ? data.mediaUrls : []),
        data.mediaUrl,
        data.thumbnailUrl,
        data.imageUrl,
      ]
    }),
  ])

  await deleteRowsByQueries(tables, COMMENT_LIKES_TABLE_ID, [
    Query.equal('userId', userId),
  ])
  await deleteRowsByFieldValues(tables, COMMENT_LIKES_TABLE_ID, 'commentId', commentIds)

  await deleteRowsByQueries(tables, LIKES_TABLE_ID, [
    Query.equal('userId', userId),
  ])
  await deleteRowsByFieldValues(tables, LIKES_TABLE_ID, 'postId', ownedPostIds)

  await deleteRowsByQueries(tables, SAVES_TABLE_ID, [
    Query.equal('userId', userId),
  ])
  await deleteRowsByFieldValues(tables, SAVES_TABLE_ID, 'postId', ownedPostIds)

  await deleteRowsByQueries(tables, REPOSTS_TABLE_ID, [
    Query.equal('userId', userId),
  ])
  await deleteRowsByFieldValues(tables, REPOSTS_TABLE_ID, 'postId', ownedPostIds)

  await deleteRowsByQueries(tables, REPORTS_TABLE_ID, [
    Query.equal('userId', userId),
  ])
  await deleteRowsByFieldValues(tables, REPORTS_TABLE_ID, 'postId', [
    userId,
    ...ownedPostIds,
    ...commentIds,
  ])

  await deleteRowsByQueries(tables, FOLLOWS_TABLE_ID, [
    Query.equal('followerId', userId),
  ])
  await deleteRowsByQueries(tables, FOLLOWS_TABLE_ID, [
    Query.equal('followeeId', userId),
  ])

  await deleteRowsByQueries(tables, BLOCKS_TABLE_ID, [
    Query.equal('blockerId', userId),
  ])
  await deleteRowsByQueries(tables, BLOCKS_TABLE_ID, [
    Query.equal('blockedUserId', userId),
  ])

  await deleteRowsByQueries(tables, REFERRALS_TABLE_ID, [
    Query.equal('referredUserId', userId),
  ])

  await deleteRowsByQueries(tables, FEED_EVENTS_TABLE_ID, [
    Query.equal('userId', userId),
  ])
  await deleteRowsByQueries(tables, FEED_EVENTS_TABLE_ID, [
    Query.equal('creatorId', userId),
  ])
  await deleteRowsByFieldValues(tables, FEED_EVENTS_TABLE_ID, 'postId', ownedPostIds)

  await deleteRowsByQueries(tables, POST_AGGREGATES_TABLE_ID, [
    Query.equal('creatorId', userId),
  ])
  await deleteRowsByIds(tables, POST_AGGREGATES_TABLE_ID, ownedPostIds)

  await deleteRowsByIds(tables, COMMENTS_TABLE_ID, commentIds)
  await deleteRowsByIds(tables, POSTS_TABLE_ID, ownedPostIds)
  await deleteRowsByQueries(tables, PROFILES_TABLE_ID, [
    Query.equal('userId', userId),
  ])
  await deleteRowsByIds(tables, PROFILES_TABLE_ID, [userId])

  await deleteAppwriteFiles(storage, appwriteFileRefs)
  await users.delete({ userId })

  return {
    ok: true,
    deletedUserId: userId,
    deletedPosts: ownedPostIds.length,
    deletedComments: commentIds.length,
  }
}

async function listAllRows(tables, tableId, queries = []) {
  const rows = []
  let cursorId = null
  let passes = 0

  while (passes < 200) {
    const result = await safeListRows(tables, tableId, [
      ...queries,
      Query.limit(100),
      ...(cursorId ? [Query.cursorAfter(cursorId)] : []),
    ])
    const fetched = Array.isArray(result.rows) ? result.rows : []
    if (fetched.length === 0) {
      break
    }

    rows.push(...fetched)
    cursorId = readString(fetched[fetched.length - 1]?.$id)
    if (!cursorId || fetched.length < 100) {
      break
    }
    passes += 1
  }

  return dedupeRows(rows)
}

async function listRowsByFieldValues(tables, tableId, field, values) {
  const rows = []
  for (const chunk of chunkArray(uniqueStrings(values), 100)) {
    if (chunk.length === 0) {
      continue
    }
    const fetched = await listAllRows(tables, tableId, [
      Query.equal(field, chunk),
    ])
    rows.push(...fetched)
  }
  return dedupeRows(rows)
}

async function collectCommentTreeIds(tables, seedIds) {
  const seen = new Set(uniqueStrings(seedIds))
  let frontier = [...seen]

  while (frontier.length > 0) {
    const next = []
    for (const chunk of chunkArray(frontier, 100)) {
      const replies = await listAllRows(tables, COMMENTS_TABLE_ID, [
        Query.equal('parentCommentId', chunk),
      ])
      for (const row of replies) {
        const rowId = readString(row?.$id)
        if (rowId && !seen.has(rowId)) {
          seen.add(rowId)
          next.push(rowId)
        }
      }
    }
    frontier = next
  }

  return [...seen]
}

async function deleteRowsByQueries(tables, tableId, queries) {
  while (true) {
    const result = await safeListRows(tables, tableId, [
      ...queries,
      Query.limit(100),
    ])
    const rows = Array.isArray(result.rows) ? result.rows : []
    if (rows.length === 0) {
      break
    }

    for (const row of rows) {
      const rowId = readString(row?.$id)
      if (rowId) {
        await safeDeleteRow(tables, tableId, rowId)
      }
    }

    if (rows.length < 100) {
      break
    }
  }
}

async function deleteRowsByFieldValues(tables, tableId, field, values) {
  for (const chunk of chunkArray(uniqueStrings(values), 100)) {
    if (chunk.length === 0) {
      continue
    }
    await deleteRowsByQueries(tables, tableId, [Query.equal(field, chunk)])
  }
}

async function deleteRowsByIds(tables, tableId, ids) {
  for (const rowId of uniqueStrings(ids)) {
    await safeDeleteRow(tables, tableId, rowId)
  }
}

async function safeListRows(tables, tableId, queries) {
  try {
    return await tables.listRows({
      databaseId: DATABASE_ID,
      tableId,
      queries,
    })
  } catch (err) {
    if (isNotFoundError(err)) {
      return { rows: [], total: 0 }
    }
    throw err
  }
}

async function safeDeleteRow(tables, tableId, rowId) {
  try {
    await tables.deleteRow({
      databaseId: DATABASE_ID,
      tableId,
      rowId,
    })
  } catch (err) {
    if (isNotFoundError(err)) {
      return
    }
    throw err
  }
}

async function deleteAppwriteFiles(storage, refs) {
  for (const ref of refs) {
    try {
      await storage.deleteFile({
        bucketId: ref.bucketId,
        fileId: ref.fileId,
      })
    } catch (err) {
      if (!isNotFoundError(err)) {
        throw err
      }
    }
  }
}

function extractAppwriteFileRefs(values) {
  const refs = []
  const seen = new Set()

  for (const value of values) {
    const ref = parseAppwriteFileRef(value)
    if (!ref) {
      continue
    }
    const key = `${ref.bucketId}:${ref.fileId}`
    if (seen.has(key)) {
      continue
    }
    seen.add(key)
    refs.push(ref)
  }

  return refs
}

function parseAppwriteFileRef(value) {
  const raw = readString(value)
  if (!raw) {
    return null
  }

  const match = raw.match(/\/storage\/buckets\/([^/]+)\/files\/([^/?]+)/i)
  if (!match) {
    return null
  }

  return {
    bucketId: decodeURIComponent(match[1]),
    fileId: decodeURIComponent(match[2]),
  }
}

function chunkArray(values, size) {
  const chunks = []
  for (let index = 0; index < values.length; index += size) {
    chunks.push(values.slice(index, index + size))
  }
  return chunks
}

function uniqueStrings(values) {
  return [...new Set((values || []).map(readString).filter(Boolean))]
}

function dedupeRows(rows) {
  const seen = new Set()
  const deduped = []
  for (const row of rows) {
    const rowId = readString(row?.$id)
    if (!rowId || seen.has(rowId)) {
      continue
    }
    seen.add(rowId)
    deduped.push(row)
  }
  return deduped
}

function isNotFoundError(err) {
  const code = Number(err?.code || 0)
  const type = String(err?.type || '').toLowerCase()
  const message = String(err?.message || '').toLowerCase()
  return code === 404 || type.includes('not_found') || message.includes('not found')
}

async function loadBlockedIds(tables, blockerId) {
  if (!blockerId) {
    return new Set()
  }

  const result = await tables.listRows({
    databaseId: DATABASE_ID,
    tableId: BLOCKS_TABLE_ID,
    queries: [
      Query.equal('blockerId', blockerId),
      Query.limit(500),
    ],
  })

  return new Set(
    (result.rows || [])
      .map((row) => readString(readRowData(row).blockedUserId))
      .filter(Boolean),
  )
}

async function fetchHomeFeed(tables, blockedIds, payload) {
  return listFilteredRows({
    tables,
    tableId: POSTS_TABLE_ID,
    blockedIds,
    limit: readPositiveInt(payload.limit, 20),
    cursorId: readString(payload.cursorId),
    queries: [
      Query.orderDesc('$createdAt'),
    ],
  })
}

async function fetchUserPosts(tables, blockedIds, payload) {
  const userIds = readStringArray(payload.userIds)
  if (userIds.length === 0) {
    return { total: 0, rows: [] }
  }

  return listFilteredRows({
    tables,
    tableId: POSTS_TABLE_ID,
    blockedIds,
    limit: readPositiveInt(payload.limit, 20),
    cursorId: readString(payload.cursorId),
    queries: [
      Query.equal('userId', userIds),
      Query.orderDesc('$createdAt'),
    ],
  })
}

async function fetchPost(tables, blockedIds, payload) {
  const postId = readString(payload.postId)
  if (!postId) {
    throw new Error('postId is required.')
  }

  let row
  try {
    row = await tables.getRow({
      databaseId: DATABASE_ID,
      tableId: POSTS_TABLE_ID,
      rowId: postId,
    })
  } catch (err) {
    if (Number(err?.code || 0) === 404) {
      return null
    }
    throw err
  }

  const userId = readString(readRowData(row).userId)
  if (userId && blockedIds.has(userId)) {
    return null
  }

  return toRowMap(row)
}

async function fetchHashtagFeed(tables, blockedIds, payload) {
  const rawTag = readString(payload.tag)
  if (!rawTag) {
    return { total: 0, rows: [] }
  }

  const normalizedTag = rawTag.startsWith('#') ? rawTag : `#${rawTag}`
  return listFilteredRows({
    tables,
    tableId: POSTS_TABLE_ID,
    blockedIds,
    limit: readPositiveInt(payload.limit, 20),
    cursorId: readString(payload.cursorId),
    queries: [
      Query.search('content', normalizedTag),
      Query.orderDesc('createdAt'),
    ],
  })
}

async function fetchComments(tables, blockedIds, payload) {
  const postId = readString(payload.postId)
  if (!postId) {
    throw new Error('postId is required.')
  }

  return listFilteredRows({
    tables,
    tableId: COMMENTS_TABLE_ID,
    blockedIds,
    limit: readPositiveInt(payload.limit, 50),
    queries: [
      Query.equal('postId', postId),
      Query.orderDesc('createdAt'),
    ],
  })
}

async function fetchSavedPosts(tables, blockedIds, payload, scopedUserId) {
  if (!scopedUserId) {
    return { total: 0, rows: [] }
  }

  const limit = readPositiveInt(payload.limit, 50)
  const cursorId = readString(payload.cursorId)

  const refs = await tables.listRows({
    databaseId: DATABASE_ID,
    tableId: SAVES_TABLE_ID,
    queries: [
      Query.equal('userId', scopedUserId),
      Query.orderDesc('createdAt'),
      Query.limit(limit),
      ...(cursorId ? [Query.cursorAfter(cursorId)] : []),
    ],
  })

  const rows = []
  for (const ref of refs.rows || []) {
    const postId = readString(readRowData(ref).postId)
    if (!postId) {
      continue
    }

    try {
      const row = await tables.getRow({
        databaseId: DATABASE_ID,
        tableId: POSTS_TABLE_ID,
        rowId: postId,
      })
      const userId = readString(readRowData(row).userId)
      if (userId && blockedIds.has(userId)) {
        continue
      }
      rows.push(toRowMap(row))
    } catch (_) {
      // Ignore deleted or inaccessible posts.
    }
  }

  return {
    total: rows.length,
    rows,
  }
}

async function listFilteredRows({
  tables,
  tableId,
  blockedIds,
  limit,
  cursorId,
  queries,
}) {
  const rows = []
  let nextCursor = cursorId
  let exhausted = false
  let passes = 0
  const batchSize = Math.min(Math.max(limit * 3, limit), 100)

  while (!exhausted && rows.length < limit && passes < 6) {
    const result = await tables.listRows({
      databaseId: DATABASE_ID,
      tableId,
      queries: [
        ...queries,
        Query.limit(batchSize),
        ...(nextCursor ? [Query.cursorAfter(nextCursor)] : []),
      ],
    })

    const fetchedRows = result.rows || []
    if (fetchedRows.length === 0) {
      exhausted = true
      break
    }

    nextCursor = fetchedRows[fetchedRows.length - 1].$id
    if (fetchedRows.length < batchSize) {
      exhausted = true
    }

    for (const row of fetchedRows) {
      const userId = readString(readRowData(row).userId)
      if (userId && blockedIds.has(userId)) {
        continue
      }

      rows.push(toRowMap(row))
      if (rows.length >= limit) {
        break
      }
    }

    passes += 1
  }

  return {
    total: rows.length,
    rows,
  }
}

function readRowData(row) {
  return row?.data && typeof row.data === 'object'
    ? row.data
    : Object.fromEntries(
        Object.entries(row || {}).filter(([key]) => !key.startsWith('$')),
      )
}

function toRowMap(row) {
  const data = readRowData(row)
  return {
    $id: String(row.$id || ''),
    $sequence:
      typeof row.$sequence === 'number' ? row.$sequence : Number(row.$sequence || 0),
    $tableId: String(row.$tableId || ''),
    $databaseId: String(row.$databaseId || DATABASE_ID),
    $createdAt: String(row.$createdAt || data.createdAt || new Date().toISOString()),
    $updatedAt: String(row.$updatedAt || row.$createdAt || data.createdAt || new Date().toISOString()),
    $permissions: Array.isArray(row.$permissions) ? row.$permissions : [],
    data,
  }
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

function readStringArray(value) {
  if (!Array.isArray(value)) {
    return []
  }
  return value.map(readString).filter(Boolean)
}

function readPositiveInt(value, fallback) {
  const parsed = Number.parseInt(String(value ?? ''), 10)
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback
  }
  return Math.min(parsed, 100)
}

function readBoolean(value, fallback = false) {
  if (value === null || value === undefined) {
    return fallback
  }
  if (typeof value === 'boolean') {
    return value
  }

  const normalized = String(value).trim().toLowerCase()
  if (!normalized) {
    return fallback
  }
  if (['true', '1', 'yes', 'on'].includes(normalized)) {
    return true
  }
  if (['false', '0', 'no', 'off'].includes(normalized)) {
    return false
  }
  return fallback
}
