// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "flutter/testing/test_metal_surface_impl.h"

#include <Metal/Metal.h>

#include "flutter/fml/logging.h"
#include "flutter/fml/platform/darwin/scoped_nsobject.h"
#include "flutter/testing/test_metal_context.h"
#include "third_party/skia/include/core/SkSurface.h"

namespace flutter {

void TestMetalSurfaceImpl::Init(const TestMetalContext::TextureInfo& texture_info,
                                const SkISize& surface_size) {
  auto texture_descriptor = fml::scoped_nsobject{
      [[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                          width:surface_size.width()
                                                         height:surface_size.height()
                                                      mipmapped:NO] retain]};

  // The most pessimistic option and disables all optimizations but allows tests
  // the most flexible access to the surface. They may read and write to the
  // surface from shaders or use as a pixel view.
  texture_descriptor.get().usage = MTLTextureUsageUnknown;

  if (!texture_descriptor) {
    FML_LOG(ERROR) << "Invalid texture descriptor.";
    return;
  }

  id<MTLTexture> texture = (__bridge id<MTLTexture>)texture_info.texture;

  GrMtlTextureInfo skia_texture_info;
  skia_texture_info.fTexture.reset([texture retain]);
  GrBackendTexture backend_texture(surface_size.width(), surface_size.height(), GrMipmapped::kNo,
                                   skia_texture_info);

  sk_sp<SkSurface> surface = SkSurface::MakeFromBackendTexture(
      test_metal_context_.GetSkiaContext().get(), backend_texture, kTopLeft_GrSurfaceOrigin, 1,
      kBGRA_8888_SkColorType, nullptr, nullptr);

  if (!surface) {
    FML_LOG(ERROR) << "Could not create Skia surface from a Metal texture.";
    return;
  }

  surface_ = std::move(surface);
  is_valid_ = true;
}

TestMetalSurfaceImpl::TestMetalSurfaceImpl(const TestMetalContext& test_metal_context,
                                           int64_t texture_id,
                                           const SkISize& surface_size)
    : test_metal_context_(test_metal_context) {
  TestMetalContext::TextureInfo texture_info =
      const_cast<TestMetalContext&>(test_metal_context_).GetTextureInfo(texture_id);
  Init(texture_info, surface_size);
}

TestMetalSurfaceImpl::TestMetalSurfaceImpl(const TestMetalContext& test_metal_context,
                                           const SkISize& surface_size)
    : test_metal_context_(test_metal_context) {
  if (surface_size.isEmpty()) {
    FML_LOG(ERROR) << "Size of test Metal surface was empty.";
    return;
  }
  TestMetalContext::TextureInfo texture_info =
      const_cast<TestMetalContext&>(test_metal_context_).CreateMetalTexture(surface_size);
  Init(texture_info, surface_size);
}

sk_sp<SkImage> TestMetalSurfaceImpl::GetRasterSurfaceSnapshot() {
  if (!IsValid()) {
    return nullptr;
  }

  if (!surface_) {
    FML_LOG(ERROR) << "Aborting snapshot because of on-screen surface "
                      "acquisition failure.";
    return nullptr;
  }

  auto device_snapshot = surface_->makeImageSnapshot();

  if (!device_snapshot) {
    FML_LOG(ERROR) << "Could not create the device snapshot while attempting "
                      "to snapshot the Metal surface.";
    return nullptr;
  }

  auto host_snapshot = device_snapshot->makeRasterImage();

  if (!host_snapshot) {
    FML_LOG(ERROR) << "Could not create the host snapshot while attempting to "
                      "snapshot the Metal surface.";
    return nullptr;
  }

  return host_snapshot;
}

// |TestMetalSurface|
TestMetalSurfaceImpl::~TestMetalSurfaceImpl() = default;

// |TestMetalSurface|
bool TestMetalSurfaceImpl::IsValid() const {
  return is_valid_;
}

// |TestMetalSurface|
sk_sp<GrDirectContext> TestMetalSurfaceImpl::GetGrContext() const {
  return IsValid() ? test_metal_context_.GetSkiaContext() : nullptr;
}

// |TestMetalSurface|
sk_sp<SkSurface> TestMetalSurfaceImpl::GetSurface() const {
  return IsValid() ? surface_ : nullptr;
}

}  // namespace flutter
