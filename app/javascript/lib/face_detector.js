// Loads the proctoring vision models once (MediaPipe Tasks, CPU).
// - Face: FaceLandmarker (478 points + eye-gaze blendshapes), falling back to the
//   lighter BlazeFace detector, then the browser's native FaceDetector.
// - Objects: EfficientDet-Lite2 (Lite0 if it can't load) limited to person / phone / book /
//   laptop: "person" also catches a second person the face model misses (far away, turned).
const VERSION = "0.10.14"
const BASE = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${VERSION}`
const MODELS = "https://storage.googleapis.com/mediapipe-models"
const LANDMARKER_MODEL = `${MODELS}/face_landmarker/face_landmarker/float16/1/face_landmarker.task`
const BLAZEFACE_MODEL = `${MODELS}/face_detector/blaze_face_short_range/float16/1/blaze_face_short_range.tflite`
const OBJECT_MODEL = `${MODELS}/object_detector/efficientdet_lite2/int8/1/efficientdet_lite2.tflite`
const OBJECT_MODEL_LIGHT = `${MODELS}/object_detector/efficientdet_lite0/int8/1/efficientdet_lite0.tflite`

let visionLoader, faceLoader, objectLoader

function vision() {
  visionLoader ||= (async () => {
    const tasks = await import(`${BASE}/vision_bundle.mjs`)
    const fileset = await tasks.FilesetResolver.forVisionTasks(`${BASE}/wasm`)
    return { tasks, fileset }
  })()
  return visionLoader
}

// detectForVideo needs strictly increasing timestamps per task.
function clock() {
  let last = 0
  return () => (last = Math.max(performance.now(), last + 1))
}

function withCount(detector) {
  detector.count = async (video) => (await detector.detect(video)).length
  return detector
}

const avg = (...pts) => ({ x: pts.reduce((s, p) => s + p.x, 0) / pts.length, y: pts.reduce((s, p) => s + p.y, 0) / pts.length })

async function landmarker() {
  const { tasks, fileset } = await vision()
  const model = await tasks.FaceLandmarker.createFromOptions(fileset, {
    baseOptions: { modelAssetPath: LANDMARKER_MODEL, delegate: "CPU" },
    runningMode: "VIDEO",
    numFaces: 3,
    outputFaceBlendshapes: true,
    minFaceDetectionConfidence: 0.5,
    minFacePresenceConfidence: 0.5,
    minTrackingConfidence: 0.5
  })
  const now = clock()
  return withCount({
    name: "landmarker",
    // Faces with a normalised box, keypoints [right eye, left eye, nose tip, mouth]
    // and gaze scores (0..1) from the eye blendshapes.
    async detect(video) {
      const result = model.detectForVideo(video, now())
      return result.faceLandmarks.map((pts, i) => {
        const xs = pts.map((p) => p.x)
        const ys = pts.map((p) => p.y)
        const x = Math.min(...xs)
        const y = Math.min(...ys)
        const shapes = Object.fromEntries((result.faceBlendshapes?.[i]?.categories || []).map((c) => [ c.categoryName, c.score ]))
        const s = (name) => shapes[name] || 0
        return {
          box: { x, y, w: Math.max(...xs) - x, h: Math.max(...ys) - y },
          keypoints: [ avg(pts[33], pts[133]), avg(pts[362], pts[263]), pts[1], pts[13] ],
          gaze: {
            down: (s("eyeLookDownLeft") + s("eyeLookDownRight")) / 2,
            up: (s("eyeLookUpLeft") + s("eyeLookUpRight")) / 2,
            left: (s("eyeLookOutLeft") + s("eyeLookInRight")) / 2,   // towards the candidate's left
            right: (s("eyeLookInLeft") + s("eyeLookOutRight")) / 2,  // towards the candidate's right
            closed: (s("eyeBlinkLeft") + s("eyeBlinkRight")) / 2
          }
        }
      })
    }
  })
}

async function blazeface() {
  const { tasks, fileset } = await vision()
  const model = await tasks.FaceDetector.createFromOptions(fileset, {
    baseOptions: { modelAssetPath: BLAZEFACE_MODEL, delegate: "CPU" },
    runningMode: "VIDEO",
    minDetectionConfidence: 0.55
  })
  const now = clock()
  return withCount({
    name: "blazeface",
    async detect(video) {
      const w = video.videoWidth || 1
      const h = video.videoHeight || 1
      return model.detectForVideo(video, now()).detections.map((d) => ({
        box: { x: d.boundingBox.originX / w, y: d.boundingBox.originY / h, w: d.boundingBox.width / w, h: d.boundingBox.height / h },
        keypoints: (d.keypoints || []).map((k) => ({ x: k.x, y: k.y }))
      }))
    }
  })
}

function native() {
  const fd = new window.FaceDetector({ fastMode: true, maxDetectedFaces: 5 })
  return withCount({
    name: "native",
    async detect(video) {
      const w = video.videoWidth || 1
      const h = video.videoHeight || 1
      return (await fd.detect(video)).map((f) => ({
        box: { x: f.boundingBox.x / w, y: f.boundingBox.y / h, w: f.boundingBox.width / w, h: f.boundingBox.height / h },
        keypoints: []
      }))
    }
  })
}

export function loadFaceDetector() {
  faceLoader ||= landmarker()
    .catch((error) => { console.warn("FaceLandmarker unavailable, using BlazeFace", error); return blazeface() })
    .catch((error) => { console.warn("MediaPipe face detection unavailable", error); return "FaceDetector" in window ? native() : null })
  return faceLoader
}

const OBJECT_LABELS = { person: "Person", "cell phone": "Mobile phone", remote: "Mobile phone", book: "Book / notes", laptop: "Another laptop / screen" }

async function objectModel(path) {
  const { tasks, fileset } = await vision()
  return tasks.ObjectDetector.createFromOptions(fileset, {
    baseOptions: { modelAssetPath: path, delegate: "CPU" },
    runningMode: "VIDEO",
    scoreThreshold: 0.3,
    maxResults: 8,
    categoryAllowlist: Object.keys(OBJECT_LABELS)
  })
}

export function loadObjectDetector() {
  objectLoader ||= (async () => {
    const model = await objectModel(OBJECT_MODEL).catch((error) => {
      console.warn("EfficientDet-Lite2 unavailable, using Lite0", error)
      return objectModel(OBJECT_MODEL_LIGHT)
    })
    const now = clock()
    return {
      // [{ kind: "cell phone", label: "Mobile phone", score: 0.71 }, ...]
      async detect(video) {
        return model.detectForVideo(video, now()).detections.map((d) => ({
          kind: d.categories[0].categoryName,
          label: OBJECT_LABELS[d.categories[0].categoryName] || d.categories[0].categoryName,
          score: d.categories[0].score
        }))
      }
    }
  })().catch((error) => { console.warn("Object detector unavailable", error); return null })
  return objectLoader
}
