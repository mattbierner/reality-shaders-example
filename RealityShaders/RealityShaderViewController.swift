import ARKit
import SceneKit
import UIKit


class RealityShaderViewController: UIViewController {
    
    // MARK: Properties
    
    @IBOutlet public var contentView: UIView?
    @IBOutlet public var tabBar: UITabBar?
    @IBOutlet public var vertextItem: UITabBarItem?
    @IBOutlet public var fragmentItem: UITabBarItem?
    @IBOutlet public var resetButton: UIButton?

    private var sceneView: ARSCNView!
    private var placedPlane = false

    private var currentFaceAnchor: ARFaceAnchor?
    
    private var planeNode: PlaneNode?
    
    private let configuration = ARWorldTrackingConfiguration()
    
    private var viewFrame: CGRect?
    
    private var lastUpdateTime: TimeInterval?
        
    // MARK: - View Controller Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tabBar?.delegate = self
        tabBar?.selectedItem = vertextItem

        resetButton?.addTarget(self, action: #selector(resetPlane), for: .touchDown)
        
        sceneView = ARSCNView(frame: self.view.bounds, options: [
            SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal
        ])
        
        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.automaticallyUpdatesLighting = true
        self.contentView?.addSubview(sceneView)
        
        viewFrame = sceneView.bounds
        
        configuration.environmentTexturing = .automatic
        configuration.planeDetection = .vertical
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Prevent auto screen dimming.
        UIApplication.shared.isIdleTimerDisabled = true
        
        // "Reset" to run the AR session for the first time.
        resetTracking()
    }
    
    func resetTracking() {
        guard ARFaceTrackingConfiguration.isSupported else { return }
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
        
    func displayErrorMessage(title: String, message: String) {
        // Present an alert informing about the error that has occurred.
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
            alertController.dismiss(animated: true, completion: nil)
            self.resetTracking()
        }
        alertController.addAction(restartAction)
        present(alertController, animated: true, completion: nil)
    }
    
    @objc func resetPlane() {
        placedPlane = false
        guard let node = planeNode else { return }
        node.contentNode.isHidden = true
    }
}

extension RealityShaderViewController: ARSessionDelegate {
    func session(_ session: ARSession, didFailWithError error: Error) {
        guard error is ARError else { return }
        
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        
        DispatchQueue.main.async {
            self.displayErrorMessage(title: "The AR session failed.", message: errorMessage)
        }
    }
}


extension RealityShaderViewController: ARSCNViewDelegate {
    
    public func renderer(_: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard planeNode == nil else { return nil }
        
        if anchor is ARPlaneAnchor {
            planeNode = PlaneNode(sceneView: sceneView, viewportSize: viewFrame!.size)
            sceneView.scene.rootNode.addChildNode(planeNode!.contentNode)
        }
        
        return nil
    }
    
    
    public func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let delta: Float = lastUpdateTime == nil ? 0.03 : Float(time - lastUpdateTime!)
        lastUpdateTime = time
        
        if planeNode != nil {
            let couldPlace = tryPlacePlaneInWorld(
                planeNode: planeNode!,
                screenLocation: CGPoint(x: viewFrame!.width / 2, y: viewFrame!.height / 2))
            
            planeNode!.contentNode.isHidden = !couldPlace
        }
                
        planeNode?.update(time: time, timeDelta: delta)
    }
    
    private func tryPlacePlaneInWorld(planeNode: PlaneNode, screenLocation: CGPoint) -> Bool {
        if placedPlane {
            return true
        }
        
        let hitTestResults = sceneView.hitTest(screenLocation, types: .existingPlaneUsingExtent)
        guard let hitTestResult = hitTestResults.first else { return false }
        
        placedPlane = true
        planeNode.contentNode.simdWorldTransform = hitTestResult.worldTransform
        
        return true
    }
}

extension RealityShaderViewController: UITabBarDelegate {
    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        if item == vertextItem {
            planeNode?.mode = .Vertex
        } else if item == fragmentItem {
            planeNode?.mode = .Fragment
        }
    }
}
