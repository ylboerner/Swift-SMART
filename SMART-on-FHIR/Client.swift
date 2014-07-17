//
//  Client.swift
//  SMART-on-FHIR
//
//  Created by Pascal Pfiffner on 6/11/14.
//  Copyright (c) 2014 SMART Platforms. All rights reserved.
//

import Foundation


let SMARTErrorDomain = "SMARTErrorDomain"


/*!
 *  A client instance handles authentication and connection to a SMART on FHIR resource server.
 */
@objc class Client {
	
	/*! The authentication protocol to use. */
	let auth: Auth
	
	/*! The server this client connects to. */
	let server: Server
	
	/*! Set to false if you don't want to use a built in web view for authentication. */
	var useWebView = true
	
	/*! Designated initializer. */
	init(auth: Auth, server: Server) {
		self.auth = auth
		server.auth = auth
		self.server = server
		logIfDebug("Initialized SMART on FHIR client against server \(server.baseURL.description)")
	}
	
	/*! Use this initializer with the appropriate server settings. */
	convenience init(serverURL: String, clientId: String, redirect: String) {
		let srv = Server(base: serverURL)
		
		var settings = ["client_id": clientId]
		let myAuth = Auth(type: AuthMethod.CodeGrant, scope: "launch/patient user/*.* patient/*.read openid profile", redirect: redirect, settings: settings)
		self.init(auth: myAuth, server: srv)
	}
	
	
	// MARK: - Preparations
	
	func ready(callback: (error: NSError?) -> ()) {
		if auth.oauth {
			callback(error: nil)
			return
		}
		
		// if we haven't initialized the auth's OAuth2 instance we likely didn't fetch the server metadata yet
		server.getMetadata { error in
			if error {
				callback(error: error)
			}
			else if self.server.authURL {
				self.auth.create(authURL: self.server.authURL!, tokenURL: self.server.tokenURL)
				callback(error: nil)
			}
			else {
				callback(error: genSMARTError("Failed to extract `authorize` URL from server metadata", 0))
			}
		}
	}
	
	var authorizing: Bool {
		get { if auth.authCallback { return true }; return false }		// cannot write "nil != authCallback?
	}
	
	/*!
	 *  Call this to start the authorization process.
	 *
	 *  If you set `useWebView` to false you will need to intercept the OAuth redirect and call `didRedirect` yourself.
	 */
	func authorize(callback: (patient: Patient?, error: NSError?) -> ()) {
		self.ready { error in
			if error {
				callback(patient: nil, error: error)
			}
			else {
				self.auth.authorize(self.useWebView) { patientId, error in
					if error || !patientId {
						callback(patient: nil, error: error)
					}
					else {
						Patient.read(patientId!, server: self.server) { resource, error in
							logIfDebug("Did read patient \(resource) with error \(error)")
							callback(patient: resource as? Patient, error: error)
						}
					}
				}
			}
		}
	}
	
	/*!
	 *  Stops any request currently in progress.
	 */
	func abort() {
		auth.abort()
		server.abortSession()
	}
	
	/*!
	 *  Call this with the redirect URL when intercepting the redirect callback in the app delegate.
	 */
	func didRedirect(redirect: NSURL) -> Bool {
		return auth.handleRedirect(redirect)
	}
	
	
	// MARK: Making Requests
	
	/*!
	 *  Request a JSON resource at the given path from the client's server.
	 */
	func requestJSON(path: String, callback: ((json: NSDictionary?, error: NSError?) -> Void)) {
		server.performJSONRequest(path, auth: auth, callback: callback)
	}
}



func logIfDebug(log: String) {
#if DEBUG
	println("SoF: \(log)")
#endif
}

func genSMARTError(text: String, code: Int?) -> NSError {
	return NSError(domain: SMARTErrorDomain, code: code ? code! : 0, userInfo: [NSLocalizedDescriptionKey: text])
}

