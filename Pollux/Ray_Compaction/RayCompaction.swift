//
//  RayCompaction.swift
//  Pollux
//
//  Created by William Ho on 11/24/17.
//  Copyright © 2017 William Ho. All rights reserved.
//

import Cocoa

class RayCompaction {
    
    static var THREADGROUP_SIZE = 512 //highest threadgroup size on Intel Graphics Card. Must match ray_compaciton.metal
    
    //References to device.
    static var device: MTLDevice! = nil
    static var defaultLibrary: MTLLibrary! = nil
    
    // Kernel used in ray stream compaction
    static var kernEvaluateRays: MTLFunction?
    static var kernEvaluateRaysPipelineState: MTLComputePipelineState! = nil
    
    static var kernPrefixSumScan: MTLFunction?
    static var kernPrefixSumScanPipelineState: MTLComputePipelineState! = nil
    
    static var kernPrefixPostSumAddition: MTLFunction?
    static var kernPrefixPostSumAdditionPipelineState: MTLComputePipelineState! = nil
    
    static var kernScatter: MTLFunction?
    static var kernScatterPipelineState: MTLComputePipelineState! = nil
    
    //Buffers
    static var valids_buffer: SharedBuffer<UInt32>!
    static var invalids_buffer: SharedBuffer<UInt32>!
    static var validScanSums_buffer: SharedBuffer<UInt32>!
    static var invalidScanSums_buffer: SharedBuffer<UInt32>!
    
    static var validationBufferSize: Int!
    
    static func setUpOnDevice(_ device: MTLDevice?, library: MTLLibrary?) {
        self.device = device!
        self.defaultLibrary = library!
        setUpShaders()
    }
    
    static func setUpBuffers(count: Int) {
        let twoPowerCeiling = ceilf(log2f(Float(count)))
        validationBufferSize = Int(powf(2.0, twoPowerCeiling))
        valids_buffer = SharedBuffer(count: Int(validationBufferSize), with: device)
        invalids_buffer = SharedBuffer(count: Int(validationBufferSize), with: device)
        let numberOfSums = (validationBufferSize + THREADGROUP_SIZE * 2 - 1) / (THREADGROUP_SIZE * 2)
        validScanSums_buffer = SharedBuffer(count: numberOfSums, with: device)
        invalidScanSums_buffer = SharedBuffer(count: numberOfSums, with: device)
    }
    
    static func setUpShaders() {
        kernEvaluateRays = defaultLibrary.makeFunction(name: "kern_evaluateRays")
        do { kernEvaluateRaysPipelineState = try device.makeComputePipelineState(function: kernEvaluateRays!) }
        catch _ { fatalError("failed to create ray evaulation pipeline state" ) }
        
        kernPrefixSumScan = defaultLibrary.makeFunction(name: "kern_prefixSumScan")
        do { kernPrefixSumScanPipelineState = try device.makeComputePipelineState(function: kernPrefixSumScan!) }
        catch _ { fatalError("failed to create prefix sum scan pipeline state" ) }
        
        kernPrefixPostSumAddition = defaultLibrary.makeFunction(name: "kern_prefixPostSumAddition")
        do { kernPrefixPostSumAdditionPipelineState = try device.makeComputePipelineState(function: kernPrefixPostSumAddition!) }
        catch _ { fatalError("failed to create prefix post sum addition pipeline state" ) }
        
        kernScatter = defaultLibrary.makeFunction(name: "kern_scatterRays")
        do { kernScatterPipelineState = try device.makeComputePipelineState(function: kernScatter!) }
        catch _ { fatalError("failed to create scatter pipeline state" ) }
    }
    
    static func encodeCompactCommands(inRays: SharedBuffer<Ray>, outRays: SharedBuffer<Ray>, using commandEncoder: MTLComputeCommandEncoder) {
        
        var numberOfRays = UInt32(inRays.count)

        // Set buffers and encode command to evaluate rays for termination
        commandEncoder.setBuffer(inRays.data, offset: 0, index: 0)
        commandEncoder.setBuffer(valids_buffer.data, offset: 0, index: 1)
        commandEncoder.setBuffer(invalids_buffer.data, offset: 0, index: 2)
        commandEncoder.setBytes(&numberOfRays, length: MemoryLayout<UInt32>.stride, index: 3)
        commandEncoder.setComputePipelineState(kernEvaluateRaysPipelineState)
        var threadsPerGroup = MTLSize(width: THREADGROUP_SIZE, height: 1, depth: 1)
        var threadGroupsDispatched = MTLSize(width: (validationBufferSize + THREADGROUP_SIZE - 1) / THREADGROUP_SIZE, height: 1, depth: 1)
        commandEncoder.dispatchThreadgroups(threadGroupsDispatched, threadsPerThreadgroup: threadsPerGroup)

        // Run Prefix Sum Scan twice for valid and invalid rays
        
        threadsPerGroup = MTLSize(width: THREADGROUP_SIZE, height: 1, depth: 1)
        threadGroupsDispatched = MTLSize(width: (validationBufferSize / 2 + THREADGROUP_SIZE - 1) / THREADGROUP_SIZE, height: 1, depth: 1)
        
        // Threadgroup level prefix sum scans
        commandEncoder.setComputePipelineState(kernPrefixSumScanPipelineState)
        
        commandEncoder.setBuffer(valids_buffer.data, offset: 0, index: 0)
        commandEncoder.setBuffer(validScanSums_buffer.data, offset: 0, index: 1)
        commandEncoder.dispatchThreadgroups(threadGroupsDispatched, threadsPerThreadgroup: threadsPerGroup)
        
        commandEncoder.setBuffer(invalids_buffer.data, offset: 0, index: 0)
        commandEncoder.setBuffer(invalidScanSums_buffer.data, offset: 0, index: 1)
        commandEncoder.dispatchThreadgroups(threadGroupsDispatched, threadsPerThreadgroup: threadsPerGroup)
        
        // Scan of scans if buffer size exceeds a single threadgroup
        if (validationBufferSize > THREADGROUP_SIZE * 2) {
            threadGroupsDispatched = MTLSize(width: 1, height: 1, depth: 1)

            commandEncoder.setBuffer(validScanSums_buffer.data, offset: 0, index: 0)
            commandEncoder.setBuffer(validScanSums_buffer.data, offset: 0, index: 1)
            commandEncoder.dispatchThreadgroups(threadGroupsDispatched, threadsPerThreadgroup: threadsPerGroup)
            
            commandEncoder.setBuffer(invalidScanSums_buffer.data, offset: 0, index: 0)
            commandEncoder.setBuffer(invalidScanSums_buffer.data, offset: 0, index: 1)
            commandEncoder.dispatchThreadgroups(threadGroupsDispatched, threadsPerThreadgroup: threadsPerGroup)

            threadGroupsDispatched = MTLSize(width: (validationBufferSize / 2 - 1) / THREADGROUP_SIZE, height: 1, depth: 1)
            
            commandEncoder.setComputePipelineState(kernPrefixPostSumAdditionPipelineState)
            
            commandEncoder.setBuffer(valids_buffer.data, offset: 0, index: 0)
            commandEncoder.setBuffer(validScanSums_buffer.data, offset: 0, index: 1)
            commandEncoder.dispatchThreadgroups(threadGroupsDispatched, threadsPerThreadgroup: threadsPerGroup)
            
            commandEncoder.setBuffer(invalids_buffer.data, offset: 0, index: 0)
            commandEncoder.setBuffer(invalidScanSums_buffer.data, offset: 0, index: 1)
            commandEncoder.dispatchThreadgroups(threadGroupsDispatched, threadsPerThreadgroup: threadsPerGroup)
        }
        
        // Scatter kernel
        threadsPerGroup = MTLSize(width: 32, height: 1, depth: 1)
        threadGroupsDispatched = MTLSize(width: (inRays.count + 31) / 32, height: 1, depth: 1)
        commandEncoder.setComputePipelineState(kernScatterPipelineState)
        commandEncoder.setBuffer(inRays.data, offset: 0, index: 0)
        commandEncoder.setBuffer(outRays.data, offset: 0, index: 1)
        commandEncoder.setBuffer(valids_buffer.data, offset: 0, index: 2)
        commandEncoder.setBuffer(invalids_buffer.data, offset: 0, index: 3)
        commandEncoder.setBytes(&numberOfRays, length: MemoryLayout<UInt32>.stride, index: 4)
        commandEncoder.dispatchThreadgroups(threadGroupsDispatched, threadsPerThreadgroup: threadsPerGroup)

    }
    // For debugging TODO: Remove this function 
    static func inspectBuffers() {
        valids_buffer.inspectData()
    }
    
}