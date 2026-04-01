"""Grayscale ResNet-18 for binary classification.

Changes from standard ResNet-18:
1. conv1: in_channels 3 -> 1 (grayscale input)
2. fc: out_features 1000 -> 1 (single logit for BCEWithLogitsLoss)

Everything else (7x7 stem, maxpool, layer1-4, avgpool) is unchanged.

Spatial shape progression for 1024x1024 input:
    Input:    [B,   1, 1024, 1024]
    conv1:    [B,  64,  512,  512]   (7x7, stride 2, pad 3)
    maxpool:  [B,  64,  256,  256]   (3x3, stride 2, pad 1)
    layer1:   [B,  64,  256,  256]
    layer2:   [B, 128,  128,  128]
    layer3:   [B, 256,   64,   64]
    layer4:   [B, 512,   32,   32]
    avgpool:  [B, 512,    1,    1]
    fc:       [B,   1]
"""

import torch
import torchvision.models as models


def grayscale_resnet18(pretrained=False):
    """Create a grayscale ResNet-18 with 1 output logit."""
    weights = "IMAGENET1K_V1" if pretrained else None
    model = models.resnet18(weights=weights)

    # 1. Replace first conv: 3 channels -> 1 channel
    #    If pretrained, average the 3-channel weights into 1 channel
    old_conv1 = model.conv1
    model.conv1 = torch.nn.Conv2d(
        1, 64, kernel_size=7, stride=2, padding=3, bias=False
    )
    if pretrained:
        with torch.no_grad():
            model.conv1.weight.copy_(old_conv1.weight.mean(dim=1, keepdim=True))

    # 2. Replace final FC: 512 features -> 1 logit
    model.fc = torch.nn.Linear(model.fc.in_features, 1)

    return model


def test_forward_pass():
    """Verify the model runs with a dummy 1024x1024 input."""
    model = grayscale_resnet18()
    model.eval()
    x = torch.randn(2, 1, 1024, 1024)
    with torch.no_grad():
        out = model(x)
    print(f"Input shape:  {x.shape}")
    print(f"Output shape: {out.shape}")
    print(f"Output values: {out.squeeze().tolist()}")
    assert out.shape == (2, 1), f"Expected (2, 1), got {out.shape}"
    print("Forward pass OK")


if __name__ == "__main__":
    test_forward_pass()
