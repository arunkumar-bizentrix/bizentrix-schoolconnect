from rest_framework import viewsets, permissions, status
from rest_framework.views import APIView

from . import push
from rest_framework.decorators import action
from rest_framework.response import Response
from .models import DeviceToken, Notification
from .serializers import DeviceTokenSerializer, NotificationSerializer


class NotificationViewSet(viewsets.ReadOnlyModelViewSet):
    """
    ViewSet for managing in-app notifications.
    Strictly scoped so users only see and modify their own notifications.
    """
    serializer_class = NotificationSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        # Strict user scoping
        user = self.request.user
        queryset = Notification.objects.filter(recipient=user).select_related(
            'student',
            'homework', 'announcement'
        )

        is_read = self.request.query_params.get('is_read')
        if is_read is not None:
            val = is_read.lower() in ['true', '1', 'yes']
            queryset = queryset.filter(is_read=val)

        return queryset

    @action(detail=True, methods=['patch', 'post'], url_path='read')
    def mark_read(self, request, pk=None):
        """
        Marks a specific notification as read.
        Enforces object-level scoping: returns 404 if notification does not belong to request.user.
        """
        notification = self.get_object()
        if not notification.is_read:
            notification.is_read = True
            notification.save(update_fields=['is_read'])
        return Response(self.get_serializer(notification).data, status=status.HTTP_200_OK)

    @action(detail=False, methods=['post', 'patch'], url_path='mark-all-read')
    def mark_all_read(self, request):
        """
        Marks all unread notifications of the current authenticated user as read.
        """
        updated_count = self.get_queryset().filter(is_read=False).update(is_read=True)
        return Response({
            'success': True,
            'marked_count': updated_count,
            'message': f"Marked {updated_count} notifications as read.",
        }, status=status.HTTP_200_OK)

    @action(detail=False, methods=['get'], url_path='unread-count')
    def unread_count(self, request):
        """
        Returns count of unread notifications for badge rendering.
        """
        count = self.get_queryset().filter(is_read=False).count()
        return Response({'unread_count': count}, status=status.HTTP_200_OK)


class DeviceRegistrationView(APIView):
    """
    POST   /api/v1/notifications/register-device/    body: {token, platform}
    DELETE /api/v1/notifications/register-device/    body: {token}

    The app registers its Firebase token after sign-in and removes it on sign
    out - otherwise the next person to use that phone would receive the
    previous user's notifications.
    """

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        serializer = DeviceTokenSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        token = serializer.validated_data['token']

        # A phone can change hands, so the row follows whoever signed in last
        # rather than being duplicated per user.
        device, created = DeviceToken.objects.update_or_create(
            token=token,
            defaults={
                'user': request.user,
                'platform': serializer.validated_data.get('platform', DeviceToken.Platform.ANDROID),
                'device_name': serializer.validated_data.get('device_name', ''),
                'is_active': True,
            },
        )

        return Response(
            {
                'registered': True,
                'created': created,
                'push_enabled': push.is_configured(),
            },
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )

    def delete(self, request):
        token = (request.data.get('token') or '').strip()
        if not token:
            return Response(
                {"detail": "token is required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Only ever removes the caller's own registration.
        removed, _ = DeviceToken.objects.filter(
            token=token, user=request.user
        ).delete()
        return Response({'removed': bool(removed)}, status=status.HTTP_200_OK)
