//
//  IntroViewController.swift
//  Noti
//
//  Created by Jari on 29/06/16.
//  Copyright © 2016 Jari Zwarts. All rights reserved.
//

import Cocoa

class IntroViewController: NSViewController {
    let appDelegate = NSApp.delegate as! AppDelegate
    let authUrl = "https://www.pushbullet.com/authorize"
    let clientId = "lIdYYNaWmj7ZJaCaycRXevhQz9yhdeJS"
    let redirectUri = "noti://redirect"
    var awc:NSWindowController?;

    override func viewDidAppear() {
        if (self.view.window != nil) {
            self.view.window!.appearance = NSAppearance(named: NSAppearance.Name.vibrantDark)
            self.view.window!.titlebarAppearsTransparent = true;
            self.view.window!.isMovableByWindowBackground = true
            self.view.window!.invalidateShadow()
        }

        NotificationCenter.default.addObserver(self, selector: #selector(IntroViewController.authSuccess(_:)), name:NSNotification.Name(rawValue: "AuthSuccess"), object: nil)
    }

    @IBOutlet weak var authBtn:NSButton!;
    @IBOutlet weak var authTxt:NSTextField!;
    @IBOutlet weak var authImg:NSImageView!;

    @objc func authSuccess(_ notification: Notification) {
        authBtn.isEnabled = false
        self.authTxt.alphaValue = 1
        self.authTxt.alphaValue = self.authBtn.alphaValue
        //self.view.window!.styleMask.subtract(NSClosableWindowMask)

        NSAnimationContext.runAnimationGroup({ (context) -> Void in
            context.duration = 0.50
            self.authTxt.animator().alphaValue = 0
            self.authBtn.animator().alphaValue = 0

            }, completionHandler: { () -> Void in
                self.authTxt.isHidden = true
                self.authBtn.isHidden = true
                self.authImg.isHidden = false
                self.authImg.alphaValue = 0

                NSAnimationContext.runAnimationGroup({ (context) -> Void in
                    context.duration = 0.50
                    self.authImg.animator().alphaValue = 1
                }, completionHandler: nil)

        })

        Timer.scheduledTimer(timeInterval: 3, target: BlockOperation(block: self.view.window!.close), selector: #selector(Operation.main), userInfo: nil, repeats: false)

    }

    private func generateNonce() -> String? {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            return nil
        }
        return bytes.toHexString()
    }

    private func prepareRedirectUri(nonce: String) -> String {
        var url = URLComponents(string: redirectUri)!
        url.queryItems = [
            URLQueryItem(name: "nonce", value: nonce)
        ]

        return url.string!
    }

    @IBAction func startAuth(_ sender: AnyObject) {
        guard let nonce = generateNonce() else { return }
        appDelegate.nonce = nonce

        var url = URLComponents(string: authUrl)!
        url.queryItems = [
            "client_id": clientId,
            "response_type": "token",
            "scope": "everything",
            "redirect_uri": prepareRedirectUri(nonce: nonce)
        ].map { URLQueryItem(name: $0, value: $1)  }

        try! NSWorkspace.shared.open(url.asURL())
    }
}
