.pragma library

// Look up the artwork's track again just before playing. Queue positions can
// move while the user browses; never substitute whatever inherited an old index.
function findTrack(queue, videoId, automix) {
  var lists = automix ? [queue.automix || [], queue.items || []] : [queue.items || [], queue.automix || []]
  for (var l = 0; l < lists.length; l++) {
    for (var i = 0; i < lists[l].length; i++) {
      var item = lists[l][i]
      if (item && item.videoId === videoId)
        return {index: typeof item.queueIndex === "number" ? item.queueIndex : i,
          automix: l === 0 ? !!automix : !automix}
    }
  }
  return null
}

function play(svc, item, automix, done) {
  svc.request("queue", {}, function(reply) {
    if (!reply.ok || !reply.data) { done(reply); return }
    var selection = findTrack(reply.data, item.videoId, automix)
    if (!selection) { svc.playItem(item, done); return }
    svc.request("queue.jump", selection, function(result) {
      // Some YouTube Music queue entries throw through selectQueueItem.
      // Its regular video-link action remains available for the same track.
      if (!result.ok && ["page-error", "out-of-range", "not-found"].indexOf(result.error) >= 0)
        svc.playItem(item, done)
      else done(result)
    })
  })
}
