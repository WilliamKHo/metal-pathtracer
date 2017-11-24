//
//  File.swift
//  Pollux
//
//  Created by William Ho on 11/24/17.
//  Copyright © 2017 William Ho. All rights reserved.
//

import Cocoa

class RayCompaction {
    
    static var THREADGROUP_SIZE = 512 //highest threadgroup size on Intel Graphics Card
    
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
    static var validation_buffer: SharedBuffer<UInt32>!
    static var scanThreadSums_buffer: SharedBuffer<UInt32>!
    
    static func setUpOnDevice(_ device: MTLDevice?, library: MTLLibrary?) {
        self.device = device!
        self.defaultLibrary = library!
        setUpShaders()
    }
    
    static func setUpShaders() {
        kernEvaluateRays = defaultLibrary.makeFunction(name: "kern_evaluateRays")
        do { kernEvaluateRaysPipelineState = try device.makeComputePipelineState(function: kernEvaluateRays!) }
        catch _ { print("failed to create ray evaulation pipeline state" ) }
        
        kernPrefixSumScan = defaultLibrary.makeFunction(name: "kern_prefixSumScan")
        do { kernPrefixSumScanPipelineState = try device.makeComputePipelineState(function: kernPrefixSumScan!) }
        catch _ { print("failed to create prefix sum scan pipeline state" ) }
        
        kernPrefixPostSumAddition = defaultLibrary.makeFunction(name: "kern_prefixPostSumAddition")
        do { kernPrefixPostSumAdditionPipelineState = try device.makeComputePipelineState(function: kernPrefixPostSumAddition!) }
        catch _ { print("failed to create prefix post sum addition pipeline state" ) }
        
        kernScatter = defaultLibrary.makeFunction(name: "kern_scatterRays")
        do { kernScatterPipelineState = try device.makeComputePipelineState(function: kernScatter!) }
        catch _ { print("failed to create scatter pipeline state" ) }
    }
    
    static func encodeCompactCommands(inRays: SharedBuffer<Ray>, outRays: SharedBuffer<Ray>, using commandEncoder: MTLComputeCommandEncoder) {
        
        // Set up bookkeeping buffers
        var twoPowerCeiling = ceilf(log2f(Float(inRays.count)))
        var numberOfRays = UInt32(inRays.count)
        var validationBufferSize = Int(powf(2.0, twoPowerCeiling))
        validation_buffer = SharedBuffer(count: Int(validationBufferSize), with: device)
        var numberOfSums = (validationBufferSize + THREADGROUP_SIZE * 2 - 1) / (THREADGROUP_SIZE * 2)
        scanThreadSums_buffer = SharedBuffer(count: numberOfSums, with: device)
        
        // Set buffers and encode command to evaluate rays for termination
        commandEncoder.setBuffer(inRays.data, offset: 0, index: 0)
        commandEncoder.setBuffer(validation_buffer.data, offset: 0, index: 1)
        commandEncoder.setBytes(&numberOfRays, length: MemoryLayout<UInt32>.stride, index: 2)
        commandEncoder.setComputePipelineState(kernEvaluateRaysPipelineState)
        var threadsPerGroup = MTLSize(width: THREADGROUP_SIZE, height: 1, depth: 1)
        var threadGroupsDispatched = MTLSize(width: (validationBufferSize + THREADGROUP_SIZE - 1) / THREADGROUP_SIZE, height: 1, depth: 1)
        commandEncoder.dispatchThreadgroups(threadGroupsDispatched, threadsPerThreadgroup: threadsPerGroup)
        
        //Set buffers for Prefix Sum Scan
        commandEncoder.setBuffer(validation_buffer.data, offset: 0, index: 0)
        commandEncoder.setBuffer(scanThreadSums_buffer.data, offset: 0, index: 1)
        //Dispatch kernels for Prefix Sum Scan
        commandEncoder.setComputePipelineState(kernPrefixSumScanPipelineState)
        threadsPerGroup = MTLSize(width: THREADGROUP_SIZE, height: 1, depth: 1)
        threadGroupsDispatched = MTLSize(width: (validationBufferSize / 2 + THREADGROUP_SIZE - 1) / THREADGROUP_SIZE, height: 1, depth: 1)
        commandEncoder.dispatchThreadgroups(threadGroupsDispatched, threadsPerThreadgroup: threadsPerGroup)
        
        //Second pass if buffer size exceeds a single threadgroup
        if (validationBufferSize > THREADGROUP_SIZE * 2) {
            commandEncoder.setBuffer(scanThreadSums_buffer.data, offset: 0, index: 0)
            threadGroupsDispatched = MTLSize(width: 1, height: 1, depth: 1)
            commandEncoder.dispatchThreadgroups(threadGroupsDispatched, threadsPerThreadgroup: threadsPerGroup)

            commandEncoder.setComputePipelineState(kernPrefixPostSumAdditionPipelineState)
            commandEncoder.setBuffer(validation_buffer.data, offset: 0, index: 0)
            threadsPerGroup = MTLSize(width: THREADGROUP_SIZE, height: 1, depth: 1)
            threadGroupsDispatched = MTLSize(width: (validationBufferSize / 2 - 1) / THREADGROUP_SIZE, height: 1, depth: 1)
            commandEncoder.dispatchThreadgroups(threadGroupsDispatched, threadsPerThreadgroup: threadsPerGroup)
        }
    }
    // For debugging TODO: Remove this function 
    static func inspectBuffers() {
        validation_buffer.inspectData()
    }
    
}