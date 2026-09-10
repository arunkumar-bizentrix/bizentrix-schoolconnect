from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response
from .models import Notification
from .serializers import NotificationSerializer


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
