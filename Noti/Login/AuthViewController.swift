//
//  ViewController.swift
//  Noti
//
//  Created by Jari on 22/06/16.
//  Copyright © 2016 Jari Zwarts. All rights reserved.
//

import Cocoa
import WebKit

class AuthViewController: NSViewController, WebFrameLoadDelegate {
    
    @IBOutlet weak var webView: WebView!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let req = URLRequest(url:URL(string:"https://www.pushbullet.com/authorize?client_id=QTVK7zATuEcu4sME8TrwLBMuoW7vC7Wr&redirect_uri=about:blank&response_type=token&scope=everything")!)
        webView.frameLoadDelegate = self
        webView.mainFrame.load(req)
    }
    
    override func viewDidAppear() {
        if let window = self.view.window {
            window.appearance = NSAppearance(named: NSAppearanceNameVibrantDark)
            window.invalidateShadow()
        }
    }
    
    func webView(_ sender: WebView!, didFinishLoadFor frame: WebFrame!) {
        //remove fugly loader that is stuck on page, even after loading (pushbullet get your shit together pls ty)
        sender.stringByEvaluatingJavaScript(from: "var uglyDivs = document.querySelectorAll(\"#onecup .agree-page div:not(#header), #onecup .agree-page #header\") if(uglyDivs.length > 0) for (var i = 0 i < uglyDivs.length i++) uglyDivs[i].remove()")

        if let ds = frame.dataSource,
            let url = ds.response.url,
            url.absoluteString.hasPrefix("about:blank") {

            let token = (url.absoluteString as NSString).substring(from: 27)
            
            print("Got token!", token, "saving and restarting PushManager")
            
            UserDefaults.standard.setValue(token, forKeyPath: "token")
            SharedAppDelegate.loadPushManager()
            
            self.view.window?.close()
            NotificationCenter.default.post(name: Notification.Name(rawValue: "AuthSuccess"), object: nil)
        }
    }

}

